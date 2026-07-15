# MarkView Sample

A lightweight, native macOS Markdown viewer.

## Text formatting

This paragraph shows **bold text**, *italic text*, and `inline code`.
You can also add [links](https://www.apple.com) inline.

### Smaller heading

Regular paragraph content wraps naturally and stays read-only.

## Lists

Unordered list:

- First item
- Second item with **bold**
- Third item

Ordered list:

1. Step one
2. Step two
3. Step three

## Code block

```swift
func greet(_ name: String) -> String {
    return "Hello, \(name)!"
}
```

## Blockquote

> This is a quoted line.
> It can span multiple lines.

## Table

| Feature      | Supported | Notes                 |
| ------------ | --------- | --------------------- |
| Headings     | Yes       | `#`–`######`          |
| **Tables**   | Yes       | GitHub-style pipes    |
| Images       | Yes       | local + remote        |
| Uneven rows  | Yes       | missing cells blank   |

## Images

Local image (resolved relative to this file):

![MarkView logo](assets/logo.png)

Remote HTTPS image (loads automatically):

![Swift logo](https://www.swift.org/apple-touch-icon.png)

Missing image (shows a fallback):

![missing](assets/does-not-exist.png)

---

That's the end of the sample.
