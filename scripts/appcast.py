#!/usr/bin/env python3
"""Adds one release to the Sparkle appcast, newest first. Creates the file when missing."""
import argparse
import email.utils
import html
import os
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC = "http://purl.org/dc/elements/1.1/"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", DC)


def notes_html(markdown):
    """The little Markdown release-notes.sh prints: `## heading` and `- item`."""
    out, in_list = [], False
    for line in markdown.splitlines():
        is_item = line.startswith("- ")
        if in_list and not is_item:
            out.append("</ul>")
            in_list = False
        if is_item and not in_list:
            out.append("<ul>")
            in_list = True
        if is_item:
            out.append(f"<li>{html.escape(line[2:])}</li>")
        elif line.startswith("## "):
            out.append(f"<h3>{html.escape(line[3:])}</h3>")
    if in_list:
        out.append("</ul>")
    return "".join(out)


def load(path):
    if os.path.exists(path):
        return ET.parse(path)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Mestre"
    return ET.ElementTree(rss)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("file", "version", "build", "url", "length", "signature", "min-os", "notes-file"):
        parser.add_argument(f"--{name}", required=True)
    args = parser.parse_args()

    tree = load(args.file)
    channel = tree.getroot().find("channel")
    # A re-run of the same release replaces its entry.
    for old in channel.findall("item"):
        if old.findtext(f"{{{SPARKLE}}}version") == args.build:
            channel.remove(old)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = args.version
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = args.build
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = args.version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = args.min_os
    if "-" in args.version:
        ET.SubElement(item, f"{{{SPARKLE}}}channel").text = "beta"
    with open(args.notes_file, encoding="utf-8") as notes:
        ET.SubElement(item, "description").text = notes_html(notes.read())
    ET.SubElement(item, "enclosure", {
        "url": args.url,
        "length": args.length,
        "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": args.signature,
    })

    position = next((i for i, child in enumerate(channel) if child.tag == "item"), len(channel))
    channel.insert(position, item)
    ET.indent(tree)
    tree.write(args.file, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
