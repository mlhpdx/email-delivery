// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;
using Amazon.Lambda.Core;
using Cppl.Utilities.AWS;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Cppl.EmailDelivery;

public static class Extensions {
    public static string? Truncate(this string? text, int length, string ellipses) =>
        text switch {
            null => null,
            string s when s.Length < length => text,
            string s => s[..(length - ellipses.Length)].TrimEnd() + ellipses
        };

    public static string? ReplaceStart(this string text, string existing, string replacement) =>
        text switch {
            null => null,
            string s when s.StartsWith(existing) => $"{replacement}{s[existing.Length..]}",
            string => throw new ArgumentException("Provided string doesn't start with the expected value.") { Data = { ["text"] = text, ["existing"] = existing } }
        };

    public static JsonArray ToJsonArray(this IEnumerable<MimeKit.InternetAddress> addresses) =>
        addresses.Select(a => a.ToString()).ToJsonArray();

    public static JsonArray ToJsonArray(this IEnumerable<string> strings) =>
         new(strings.Select(s => JsonValue.Create(s)).ToArray());

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

        using var raw_message_stream = new SeekableS3Stream(_s3, bucket_name, message_key, 1024*1024, 100);
        using var message = await MimeKit.MimeMessage.LoadAsync(raw_message_stream);
        var message_id = message.MessageId ?? Path.GetFileName(message_key);

        await Console.Out.WriteLineAsync($"\nMessage-ID: {message.MessageId}");
        await Console.Out.WriteLineAsync($"\nFrom {message.From}\nTo: {string.Join(", ", message.To)}\nCc: {string.Join(", ", message.Cc)}\nBcc: {string.Join(", ", message.Bcc)}\nSubject: {message.Subject}");

        var content_prefix = message_key.ReplaceStart("inbox/", "content/");

        async Task<string> decode_part_as_content(MimeKit.MimePart part, int index, [CallerArgumentExpression("part")] string prefix = null!) {
            var part_key = $"{content_prefix}/{part.ContentDisposition?.FileName ?? part.ContentId ?? $"{prefix??"part"}_{index}.{part.ContentType.MediaType}"}"; 
            using (var upload = new S3UploadStream(_s3, bucket_name, part_key)) {
                await part.Content.DecodeToAsync(upload);
            }
            return part_key;
        }

        var body_parts = await Task.WhenAll(message.BodyParts.Cast<MimeKit.MimePart>()
            .Select((body, index) => decode_part_as_content(body, index)));

        var attachments = await Task.WhenAll(message.Attachments.Cast<MimeKit.MimePart>()
            .Select((attachment, index) => decode_part_as_content(attachment, index)));

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
                [ "body" ] = body_parts.ToJsonArray(),
                [ "attachments" ] = attachments.ToJsonArray()
            }
        };

        var contents = new[] {
            new { label = "text", content = message.TextBody, uri = $"s3://{bucket_name}/{content_prefix}/_body.txt" },
            new { label = "html", content = message.HtmlBody, uri = $"s3://{bucket_name}/{content_prefix}/_body.html"},
            new { label = "meta.json", content = result.ToString(), uri = $"s3://{bucket_name}/{content_prefix}/_meta.json"}
        }.Where(c => c.content != null);

        await Console.Out.WriteLineAsync($"\nContent Uris: {string.Join("\n - ", contents.Select(c => c.uri))}.");

        foreach(var c in contents) {
            result["content"]![c.label] = c.uri;
        }

        await Task.WhenAll(contents.Select(async c => {
            using (var stream = new S3UploadStream(_s3, c.uri)) {
                await c.content.CopyToStream(stream)!;
            }
        }));

        return result;
    }
}
