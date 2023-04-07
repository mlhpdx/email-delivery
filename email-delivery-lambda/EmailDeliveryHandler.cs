// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
using System.Text.Json;
using System.Text.Json.Nodes;
using Amazon.Lambda.Core;
using Cppl.Utilities.AWS;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Cppl.EmailDelivery;

public static class Extensions {
    public static string? Truncate(this string? text, int length, string ellipses) {
        return text switch {
            null => null,
            string s when s.Length < length => text,
            string s => s.Substring(0, length - ellipses.Length).TrimEnd() + ellipses
        };
    }

    public static string? ReplaceStart(this string text, string existing, string replacement)
    {
        return text switch {
            null => null,
            string s when s.StartsWith(existing) => $"{replacement}{s.Substring(existing.Length)}",
            string s => throw new ArgumentException("Provided string doesn't start with the expected value.") { Data = { ["text"] = text, ["existing"] = existing } }
        };
    }

    public static JsonArray ToJsonArray(this IEnumerable<MimeKit.InternetAddress> addresses) {
        return addresses.Select(a => a.ToString()).ToJsonArray();
    }

    public static JsonArray ToJsonArray(this IEnumerable<string> strings) {
        return new JsonArray(strings.Select(s => JsonValue.Create(s)).ToArray());
    }

    public static Task? CopyToStream(this string text, Stream stream) {
        if (text == null) return null;
        using var ms = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(text));
        return ms.CopyToAsync(stream);
    }
}

public class Function
{
    static Function() { }
    
    public Function() : this(new Amazon.S3.AmazonS3Client()) { /* start X-Ray here */ }
    public Function(Amazon.S3.IAmazonS3 s3) { _s3 = s3; }

    Amazon.S3.IAmazonS3 _s3;

    public async Task<JsonObject> FunctionHandler(JsonObject request, ILambdaContext context)
    {
        var detail = request.TryGetPropertyValue("detail", out var d) ? d as JsonObject 
            : throw new InvalidDataException("Request is missing detail.");

        var bucket = detail?.TryGetPropertyValue("bucket", out var b) == true ? b as JsonObject 
            : throw new InvalidDataException("Request is missing bucket.");
                        
        var @object = detail?.TryGetPropertyValue("object", out var o) == true ? o as JsonObject 
            : throw new InvalidDataException("Request is missing object.");

        var bucket_name = bucket?.TryGetPropertyValue("name", out var n) == true ? (string?)(n as JsonValue)
            : throw new InvalidDataException("Request is missing bucket name.");
          
        var message_key = @object?.TryGetPropertyValue("key", out var k) == true ? (string?)(k as JsonValue)
            : throw new InvalidDataException("Request is object key.");

        if (string.IsNullOrEmpty(bucket_name)) throw new InvalidDataException("Request has null or empty bucket name.");
        if (string.IsNullOrEmpty(message_key)) throw new InvalidDataException("Request has null or empty object key.");

        await Console.Out.WriteLineAsync($"\nBucket {bucket_name}\nKey: {message_key}");

        using var payload = new SeekableS3Stream(_s3, bucket_name, message_key, 1024*1024, 100);
        using var message = await MimeKit.MimeMessage.LoadAsync(payload);
        var message_id = message.MessageId ?? Path.GetFileName(message_key);

        await Console.Out.WriteLineAsync($"\nMessage-ID: {message.MessageId}");
        await Console.Out.WriteLineAsync($"\nFrom {message.From}\nTo: {string.Join(", ", message.To)}\nCc: {string.Join(", ", message.Cc)}\nBcc: {string.Join(", ", message.Bcc)}\nSubject: {message.Subject}");

        await Task.WhenAll(message.BodyParts.Select(p => p.WriteToAsync(new S3UploadStream(_s3, bucket_name, $"{message_key}/{p.ContentType.MediaSubtype}"), true)));

        var content_prefix = message_key.ReplaceStart("inbox/", "content/");
        var text_body_key = $"{content_prefix}/_body.txt";
        var html_body_key = $"{content_prefix}/_body.html";
        var meta_json_key = $"{content_prefix}/_meta.json";

        await Console.Out.WriteLineAsync($"\nContent keys: {text_body_key}, {html_body_key}, {meta_json_key}.");

        using var text_body_stream = new S3UploadStream(_s3, bucket_name, text_body_key);
        using var html_body_stream = new S3UploadStream(_s3, bucket_name, html_body_key);
        using var meta_json_stream = new S3UploadStream(_s3, bucket_name, meta_json_key);

        await Task.WhenAll(new[] {
            message.TextBody?.CopyToStream(text_body_stream) ?? Task.CompletedTask,
            message.HtmlBody?.CopyToStream(html_body_stream) ?? Task.CompletedTask,
        });

        async Task<string> decode_attachment_to_inbox(MimeKit.MimePart attachment) {
            var attachment_key = $"{content_prefix}/{attachment.ContentDisposition?.FileName ?? attachment.ContentId}"; 
            using var upload = new S3UploadStream(_s3, bucket_name, attachment_key);
            await attachment.Content.DecodeToAsync(upload);
            return attachment_key;
        }

        var attachments = await Task.WhenAll(message.Attachments.Cast<MimeKit.MimePart>()
            .Select(attachment => decode_attachment_to_inbox(attachment)));

        await Console.Out.WriteLineAsync($"\nAttachments: {string.Join(", ", attachments)}");

        var recipients = message.GetRecipients().Select(r => r.Address).Distinct();

        var result = new JsonObject() {
            [ "result" ] = "OK",
            [ "message_id"] = message_id,
            [ "payload_uri" ] = $"s3://{bucket_name}/{message_key}",
            [ "from" ] = $"{message.From}",
            [ "to" ] = message.To.ToJsonArray(),
            [ "cc" ] = message.Cc.ToJsonArray(),
            [ "bcc" ] = message.Bcc.ToJsonArray(),
            [ "recipients" ] = recipients.ToJsonArray(),
            [ "subject" ] = message.Subject,
            [ "date" ] =  $"{message.Date.UtcDateTime:o}",
            [ "text" ] = message.TextBody,
            [ "content" ] = new JsonObject() {
                [ "text" ] = $"s3://{bucket_name}/{text_body_key}",
                [ "html" ] = $"s3://{bucket_name}/{html_body_key}",
                [ "attachments" ] = attachments.ToJsonArray()
            }
        };

        await (result.ToString().CopyToStream(meta_json_stream) ?? Task.CompletedTask);

        return result;
    }
}
