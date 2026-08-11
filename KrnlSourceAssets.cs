using System.Reflection;
using System.Xml.Linq;
using Drawing = System.Drawing;

namespace OrbitAvalonia;

internal static class KrnlSourceAssets
{
    public static Drawing.Image? LoadPng(string key)
    {
        using var source = Assembly.GetExecutingAssembly().GetManifestResourceStream("OrbitAvalonia.KrnlSource.xml");
        if (source is null) return null;
        var document = XDocument.Load(source);
        var encoded = document.Root?.Elements("data")
            .FirstOrDefault(item => string.Equals((string?)item.Attribute("name"), key, StringComparison.Ordinal))
            ?.Element("value")?.Value;
        if (string.IsNullOrWhiteSpace(encoded)) return null;
        var serialized = Convert.FromBase64String(encoded);
        var start = Find(serialized, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
        if (start < 0) return null;
        var end = FindPngEnd(serialized, start);
        if (end <= start) return null;
        using var stream = new MemoryStream(serialized, start, end - start, writable: false);
        using var image = Drawing.Image.FromStream(stream);
        return new Drawing.Bitmap(image);
    }

    private static int Find(byte[] data, byte[] signature)
    {
        for (var i = 0; i <= data.Length - signature.Length; i++)
        {
            var matches = true;
            for (var j = 0; j < signature.Length; j++)
                if (data[i + j] != signature[j]) { matches = false; break; }
            if (matches) return i;
        }
        return -1;
    }

    private static int FindPngEnd(byte[] data, int start)
    {
        var offset = start + 8;
        while (offset + 12 <= data.Length)
        {
            var length = (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
            if (length < 0 || offset + 12 + length > data.Length) return -1;
            var isEnd = data[offset + 4] == (byte)'I' && data[offset + 5] == (byte)'E' && data[offset + 6] == (byte)'N' && data[offset + 7] == (byte)'D';
            offset += 12 + length;
            if (isEnd) return offset;
        }
        return -1;
    }
}
