using System.Text;
using System.Text.Json;

namespace OrbitAvalonia;

/// <summary>
/// Applies Monaco's compact edit events to the native workspace copy without
/// serializing and crossing the WebView boundary with the whole document for
/// every keystroke.
/// </summary>
internal static class EditorContentDelta
{
    private readonly record struct Change(int Offset, int Length, string Text);

    public static bool TryApply(JsonElement changesElement, string current, out string updated)
    {
        updated = current;
        if (changesElement.ValueKind != JsonValueKind.Array || changesElement.GetArrayLength() > 4096)
        {
            return false;
        }

        var changes = new List<Change>(changesElement.GetArrayLength());
        foreach (var element in changesElement.EnumerateArray())
        {
            if (element.ValueKind != JsonValueKind.Object ||
                !element.TryGetProperty("offset", out var offsetElement) ||
                !offsetElement.TryGetInt32(out var offset) ||
                !element.TryGetProperty("length", out var lengthElement) ||
                !lengthElement.TryGetInt32(out var length) ||
                !element.TryGetProperty("text", out var textElement) ||
                textElement.ValueKind != JsonValueKind.String ||
                offset < 0 || length < 0 || offset > current.Length - length)
            {
                return false;
            }

            changes.Add(new Change(offset, length, textElement.GetString() ?? string.Empty));
        }

        if (changes.Count == 0)
        {
            return true;
        }

        changes.Sort(static (left, right) => right.Offset.CompareTo(left.Offset));
        var nextRangeStart = current.Length;
        foreach (var change in changes)
        {
            if (change.Offset + change.Length > nextRangeStart)
            {
                return false;
            }
            nextRangeStart = change.Offset;
        }

        var builder = new StringBuilder(current);
        foreach (var change in changes)
        {
            builder.Remove(change.Offset, change.Length);
            builder.Insert(change.Offset, change.Text);
        }
        updated = builder.ToString();
        return true;
    }
}
