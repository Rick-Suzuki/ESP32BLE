#!/usr/bin/env python3
"""Generate Help/complete-user-manual.html from the Quick Help pages.

Run from any directory with:
    python3 Help/generate_user_manual.py

Use --check in automation to validate that the committed manual is current.
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse


HELP_DIRECTORY = Path(__file__).resolve().parent
SOURCE_DIRECTORY = HELP_DIRECTORY / "html"
OUTPUT_FILENAME = "complete-user-manual.html"
CONTENTS_ID = "contents"


@dataclass(frozen=True)
class PageDefinition:
    filename: str


@dataclass(frozen=True)
class SectionDefinition:
    title: str
    identifier: str
    pages: tuple[PageDefinition, ...]


@dataclass(frozen=True)
class ChapterDefinition:
    title: str
    identifier: str
    pages: tuple[PageDefinition, ...] = ()
    sections: tuple[SectionDefinition, ...] = ()


@dataclass(frozen=True)
class ImageReference:
    source: str
    allows_missing: bool


def pages(*filenames: str) -> tuple[PageDefinition, ...]:
    return tuple(PageDefinition(filename) for filename in filenames)


MANUAL_CHAPTERS = (
    ChapterDefinition(
        "Connect to Mac",
        "connect-to-mac",
        pages(
            "connect-mac.html",
            "connect-mac-setup.html",
            "connect-mac-accessibility.html",
            "connect-mac-connection.html",
            "connect-mac-test.html",
        ),
    ),
    ChapterDefinition(
        "Configure ESP32BLE",
        "configure-esp32ble",
        pages(
            "configure-esp32ble-what-you-need.html",
            "configure-esp32ble-board-usb.html",
            "configure-esp32ble-firmware.html",
            "configure-esp32ble-install.html",
            "configure-esp32ble-keyboard.html",
        ),
    ),
    ChapterDefinition(
        "Connect Your iOS Device to ESP32BLE",
        "connect-ios-to-esp32ble",
        pages(
            "connect-esp32ble-mode.html",
            "connect-esp32ble-find.html",
            "connect-esp32ble-connect.html",
            "connect-esp32ble-test.html",
            "connect-esp32ble-reconnect.html",
        ),
    ),
    ChapterDefinition(
        "Using ESP",
        "using-esp",
        sections=(
            SectionDefinition(
                "Getting Started",
                "getting-started",
                pages(
                    "using-esp-getting-started-overview.html",
                    "using-esp-main.html",
                    "using-esp-screens.html",
                    "using-esp-buttons.html",
                ),
            ),
            SectionDefinition(
                "Creating and Editing",
                "creating-and-editing",
                pages(
                    "using-esp-creating-editing-overview.html",
                    "using-esp-edit.html",
                    "using-esp-soft-editor.html",
                    "using-esp-quick.html",
                ),
            ),
            SectionDefinition(
                "Commands and Controls",
                "commands-and-controls",
                pages(
                    "using-esp-commands-overview.html",
                    "using-esp-keyboard.html",
                    "using-esp-speech.html",
                    "using-esp-midi.html",
                    "using-esp-widgets.html",
                ),
            ),
            SectionDefinition(
                "Media and Appearance",
                "media-and-appearance",
                pages(
                    "using-esp-media-overview.html",
                    "using-esp-images.html",
                    "using-esp-audio.html",
                ),
            ),
            SectionDefinition(
                "Files and Settings",
                "files-and-settings",
                pages(
                    "using-esp-files-settings-overview.html",
                    "using-esp-import-export.html",
                    "using-esp-backup.html",
                    "using-esp-settings.html",
                ),
            ),
        ),
    ),
    ChapterDefinition(
        "Troubleshooting",
        "troubleshooting",
        pages(
            "troubleshooting-esp32-not-found.html",
            "troubleshooting-esp32-connection.html",
            "troubleshooting-keyboard.html",
            "troubleshooting-mac.html",
            "troubleshooting-buttons.html",
        ),
    ),
)


class MainContentExtractor(HTMLParser):
    """Extracts and transforms exactly one <main> element using HTMLParser."""

    def __init__(
        self,
        source_path: Path,
        page_id: str,
        heading_level: int,
        heading_number: str,
    ) -> None:
        super().__init__(convert_charrefs=False)
        self.source_path = source_path
        self.page_id = page_id
        self.heading_level = heading_level
        self.heading_number = heading_number
        self.main_depth = 0
        self.main_count = 0
        self.heading_count = 0
        self.in_heading = False
        self.heading_prefix_pending = False
        self.heading_text: list[str] = []
        self.content: list[str] = []
        self.image_sources: list[ImageReference] = []

    @property
    def title(self) -> str:
        return re.sub(r"^\s*\d+\.\s*", "", html.unescape("".join(self.heading_text)).strip())

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "main":
            if self.main_depth:
                raise ValueError(f"Nested <main> in {self.source_path.name}")
            self.main_count += 1
            self.main_depth = 1
            return
        if not self.main_depth:
            return
        if tag == "h2":
            self.heading_count += 1
            if self.heading_count > 1:
                raise ValueError(f"Multiple page headings in {self.source_path.name}")
            self.in_heading = True
            self.heading_prefix_pending = True
            self.content.append(f'<h{self.heading_level} id="{self.page_id}" class="manual-page-title">')
            return
        if tag == "img":
            attributes_by_name = dict(attrs)
            source = attributes_by_name.get("src")
            if source:
                self.image_sources.append(
                    ImageReference(
                        resolve_image_source(source, self.source_path),
                        attributes_by_name.get("data-planned-image") == "true",
                    )
                )
                attrs = [
                    (name, resolve_image_source(value, self.source_path) if name == "src" and value else value)
                    for name, value in attrs
                ]
                self.content.append(render_start_tag(tag, attrs))
                return
        self.content.append(self.get_starttag_text())

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.main_depth:
            if tag == "img":
                attributes_by_name = dict(attrs)
                source = attributes_by_name.get("src")
                if source:
                    self.image_sources.append(
                        ImageReference(
                            resolve_image_source(source, self.source_path),
                            attributes_by_name.get("data-planned-image") == "true",
                        )
                    )
                    attrs = [
                        (name, resolve_image_source(value, self.source_path) if name == "src" and value else value)
                        for name, value in attrs
                    ]
                    self.content.append(render_start_tag(tag, attrs, self_closing=True))
                    return
            self.content.append(self.get_starttag_text())

    def handle_endtag(self, tag: str) -> None:
        if tag == "main":
            if not self.main_depth:
                return
            self.main_depth = 0
            return
        if not self.main_depth:
            return
        if tag == "h2":
            self.in_heading = False
            self.content.append(f"</h{self.heading_level}>")
            return
        self.content.append(f"</{tag}>")

    def handle_data(self, data: str) -> None:
        if self.main_depth:
            if self.in_heading:
                self.heading_text.append(data)
                if self.heading_prefix_pending:
                    data = f"{self.heading_number}. " + re.sub(r"^\s*\d+\.\s*", "", data)
                    self.heading_prefix_pending = False
            self.content.append(data)

    def handle_entityref(self, name: str) -> None:
        if self.main_depth:
            value = f"&{name};"
            self.content.append(value)
            if self.in_heading:
                self.heading_text.append(value)

    def handle_charref(self, name: str) -> None:
        if self.main_depth:
            value = f"&#{name};"
            self.content.append(value)
            if self.in_heading:
                self.heading_text.append(value)

    def handle_comment(self, data: str) -> None:
        if self.main_depth:
            self.content.append(f"<!--{data}-->")

    def handle_decl(self, decl: str) -> None:
        if self.main_depth:
            self.content.append(f"<!{decl}>")

    def handle_pi(self, data: str) -> None:
        if self.main_depth:
            self.content.append(f"<?{data}>")

    def result(self) -> tuple[str, str, tuple[ImageReference, ...]]:
        if self.main_depth:
            raise ValueError(f"Unclosed <main> in {self.source_path.name}")
        if self.main_count != 1:
            raise ValueError(f"Expected one <main> in {self.source_path.name}, found {self.main_count}")
        if self.heading_count != 1 or not self.title:
            raise ValueError(f"Expected one non-empty <h2> in {self.source_path.name}")
        return "".join(self.content).strip(), self.title, tuple(self.image_sources)


@dataclass(frozen=True)
class ExtractedPage:
    filename: str
    title: str
    identifier: str
    heading_number: str
    content: str


def all_source_pages() -> tuple[PageDefinition, ...]:
    ordered: list[PageDefinition] = []
    for chapter in MANUAL_CHAPTERS:
        ordered.extend(chapter.pages)
        for section in chapter.sections:
            ordered.extend(section.pages)
    return tuple(ordered)


def page_identifier(filename: str) -> str:
    return f"page-{Path(filename).stem}"


def render_start_tag(
    tag: str,
    attrs: list[tuple[str, str | None]],
    self_closing: bool = False,
) -> str:
    attributes = "".join(
        f" {name}" if value is None else f' {name}="{html.escape(value, quote=True)}"'
        for name, value in attrs
    )
    return f"<{tag}{attributes}{' /' if self_closing else ''}>"


def resolve_image_source(source: str, source_path: Path) -> str:
    parsed = urlparse(source)
    if parsed.scheme or parsed.netloc or source.startswith("/"):
        raise ValueError(f"External or absolute image reference in {source_path.name}: {source}")
    image_path = (source_path.parent / parsed.path).resolve()
    try:
        relative_path = image_path.relative_to(HELP_DIRECTORY.resolve())
    except ValueError as error:
        raise ValueError(f"Image escapes Help directory in {source_path.name}: {source}") from error
    resolved_source = relative_path.as_posix()
    if parsed.query:
        resolved_source += f"?{parsed.query}"
    if parsed.fragment:
        resolved_source += f"#{parsed.fragment}"
    return resolved_source


def validate_image_references(
    image_references: tuple[ImageReference, ...],
    source_path: Path,
) -> None:
    reported_missing: set[str] = set()
    for reference in image_references:
        image_path = (HELP_DIRECTORY / urlparse(reference.source).path).resolve()
        if image_path.is_file():
            continue
        if not reference.allows_missing:
            raise ValueError(f"Missing local image in {source_path.name}: {reference.source}")
        if reference.source in reported_missing:
            continue
        reported_missing.add(reference.source)
        print(
            f"Manual generation warning: Missing planned image in {source_path.name}: "
            f"{Path(urlparse(reference.source).path).name}",
            file=sys.stderr,
        )


def extract_page(
    definition: PageDefinition,
    heading_level: int,
    heading_number: str,
) -> ExtractedPage:
    source_path = SOURCE_DIRECTORY / definition.filename
    if not source_path.is_file():
        raise ValueError(f"Missing source Help page: {definition.filename}")
    identifier = page_identifier(definition.filename)
    parser = MainContentExtractor(source_path, identifier, heading_level, heading_number)
    parser.feed(source_path.read_text(encoding="utf-8"))
    parser.close()
    content, title, image_sources = parser.result()
    validate_image_references(image_sources, source_path)
    return ExtractedPage(definition.filename, title, identifier, heading_number, content)


def render_page(page: ExtractedPage) -> str:
    return f'''<article class="manual-page" data-source="{html.escape(page.filename)}">
{page.content}
</article>'''


def render_page_contents(pages_to_render: list[ExtractedPage]) -> str:
    return "\n".join(
        f'                <li><a href="#{page.identifier}">{page.heading_number}. {html.escape(page.title)}</a></li>'
        for page in pages_to_render
    )


def render_toc(chapter_pages: dict[str, list[ExtractedPage]]) -> str:
    parts = [
        '<nav class="manual-toc" aria-labelledby="contents">',
        f'    <h2 id="{CONTENTS_ID}">Contents</h2>',
        '    <ol>',
        '        <li><a href="#introduction">1. Introduction</a></li>',
    ]
    for chapter_index, chapter in enumerate(MANUAL_CHAPTERS, start=2):
        chapter_number = str(chapter_index)
        parts.append(
            f'        <li><a href="#chapter-{chapter.identifier}">{chapter_number}. {html.escape(chapter.title)}</a>'
        )
        if chapter.sections:
            parts.append("            <ol>")
            for section_index, section in enumerate(chapter.sections, start=1):
                section_number = f"{chapter_number}.{section_index}"
                parts.append(
                    f'                <li><a href="#section-{section.identifier}">{section_number}. {html.escape(section.title)}</a>'
                )
                parts.append("                    <ol>")
                parts.append(render_page_contents(chapter_pages[section.identifier]))
                parts.append("                    </ol>")
                parts.append("                </li>")
            parts.append("            </ol>")
        else:
            parts.append("            <ol>")
            parts.append(render_page_contents(chapter_pages[chapter.identifier]))
            parts.append("            </ol>")
        parts.append("        </li>")
    parts.extend(["    </ol>", "</nav>"])
    return "\n".join(parts)


def render_manual() -> str:
    source_pages = all_source_pages()
    filenames = [page.filename for page in source_pages]
    if len(filenames) != 40:
        raise ValueError(f"Expected 40 Quick Help pages, found {len(filenames)} in the manifest")
    if len(set(filenames)) != len(filenames):
        raise ValueError("Duplicate source page in the manual manifest")

    chapter_pages: dict[str, list[ExtractedPage]] = {}
    all_identifiers = {CONTENTS_ID, "introduction"}
    for chapter_index, chapter in enumerate(MANUAL_CHAPTERS, start=2):
        chapter_number = str(chapter_index)
        if chapter.sections:
            for section_index, section in enumerate(chapter.sections, start=1):
                section_identifier = f"section-{section.identifier}"
                if section_identifier in all_identifiers:
                    raise ValueError(f"Duplicate generated anchor: {section_identifier}")
                all_identifiers.add(section_identifier)
                section_number = f"{chapter_number}.{section_index}"
                extracted = [
                    extract_page(
                        page,
                        heading_level=4,
                        heading_number=f"{section_number}.{page_index}",
                    )
                    for page_index, page in enumerate(section.pages, start=1)
                ]
                chapter_pages[section.identifier] = extracted
                for page in extracted:
                    if page.identifier in all_identifiers:
                        raise ValueError(f"Duplicate generated anchor: {page.identifier}")
                    all_identifiers.add(page.identifier)
        else:
            extracted = [
                extract_page(
                    page,
                    heading_level=3,
                    heading_number=f"{chapter_number}.{page_index}",
                )
                for page_index, page in enumerate(chapter.pages, start=1)
            ]
            chapter_pages[chapter.identifier] = extracted
            for page in extracted:
                if page.identifier in all_identifiers:
                    raise ValueError(f"Duplicate generated anchor: {page.identifier}")
                all_identifiers.add(page.identifier)

    for chapter in MANUAL_CHAPTERS:
        chapter_identifier = f"chapter-{chapter.identifier}"
        if chapter_identifier in all_identifiers:
            raise ValueError(f"Duplicate generated anchor: {chapter_identifier}")
        all_identifiers.add(chapter_identifier)

    toc = render_toc(chapter_pages)
    chapters: list[str] = []
    for chapter_index, chapter in enumerate(MANUAL_CHAPTERS, start=2):
        chapter_number = str(chapter_index)
        chapter_id = f"chapter-{chapter.identifier}"
        parts = [
            f'<section class="manual-chapter" aria-labelledby="{chapter_id}">',
            f'    <h2 id="{chapter_id}">{chapter_number}. {html.escape(chapter.title)}</h2>',
        ]
        if chapter.sections:
            for section_index, section in enumerate(chapter.sections, start=1):
                section_id = f"section-{section.identifier}"
                section_number = f"{chapter_number}.{section_index}"
                parts.extend([
                    f'    <section class="manual-subsection" aria-labelledby="{section_id}">',
                    f'        <h3 id="{section_id}">{section_number}. {html.escape(section.title)}</h3>',
                ])
                parts.extend(f"        {line}" for page in chapter_pages[section.identifier] for line in render_page(page).splitlines())
                parts.append('    </section>')
        else:
            parts.extend(f"    {line}" for page in chapter_pages[chapter.identifier] for line in render_page(page).splitlines())
        parts.append('</section>')
        chapters.append("\n".join(parts))

    document = f'''<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="css/help.css">
    <script defer src="js/help-images.js"></script>
    <title>ESP User Manual</title>
    <style>
        .user-manual {{ background: #ffffff; color: #1c1c1e; }}
        .user-manual main {{ width: min(100%, 48rem); margin: 0 auto; padding: clamp(1rem, 4vw, 2rem); }}
        html.esp-ipad .user-manual main {{ width: min(88vw, 72rem); }}
        .user-manual h1 {{ font-size: clamp(1.75rem, 5vw, 2.25rem); line-height: 1.2; }}
        .user-manual h2 {{ margin-top: 2.5rem; padding-top: 1rem; border-top: 1px solid #d1d1d6; }}
        .user-manual h3 {{ margin-top: 2rem; }}
        .user-manual h4 {{ margin-top: 1.5rem; font-size: 1.0625rem; }}
        .user-manual .manual-toc {{ margin: 1.5rem 0 2rem; padding: 1rem; background: #f2f2f7; }}
        .user-manual .manual-toc h2 {{ margin: 0 0 0.75rem; padding: 0; border: 0; }}
        .user-manual .manual-toc ol {{ margin: 0.5rem 0; list-style: none; }}
        .user-manual .manual-toc > ol {{ padding-inline-start: 0; }}
        .user-manual .manual-page {{ margin: 1.25rem 0 2rem; }}
        .user-manual .manual-source .visual-help-page {{ display: block; min-height: 0; background: transparent; }}
        .user-manual .manual-source .visual-help,
        .user-manual .manual-source .help-step,
        .user-manual .manual-source .help-setup {{ display: block; min-height: 0; }}
        .user-manual .manual-source figure {{ margin: 1rem 0; }}
        .user-manual .manual-source img {{ max-width: 100%; height: auto; }}
    </style>
</head>
<body class="user-manual">
    <main>
        <header>
            <h1>ESP User Manual</h1>
            <p>ESP is an iPhone and iPad application with programmable buttons that can control supported targets through ESPMacHelper or an ESP32-S3 device.</p>
        </header>
        {toc}
        <section class="manual-chapter" aria-labelledby="introduction">
            <h2 id="introduction">1. Introduction</h2>
            <p>Use this manual for the complete offline reference. Quick Help remains available in ESP for focused, step-by-step guidance.</p>
        </section>
        {"\n        ".join(chapters)}
    </main>
</body>
</html>
'''

    for identifier in re.findall(r'\bid="([^"]+)"', document):
        if document.count(f'id="{identifier}"') != 1:
            raise ValueError(f"Duplicate generated anchor in output: {identifier}")
    href_targets = re.findall(r'href="#([^"]+)"', document)
    unresolved = sorted(set(href_targets) - set(re.findall(r'\bid="([^"]+)"', document)))
    if unresolved:
        raise ValueError(f"Unresolved internal anchors: {', '.join(unresolved)}")
    if document.count('data-source=') != 40:
        raise ValueError("A source page was omitted from the generated manual")
    external_resources = re.findall(r'(?:src|href)="(?:https?:)?//[^\"]+"', document)
    if external_resources:
        raise ValueError(f"External resource found in generated manual: {external_resources[0]}")
    return document


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the offline ESP HTML user manual.")
    parser.add_argument("--check", action="store_true", help="Verify the generated manual is current without writing it.")
    arguments = parser.parse_args()

    try:
        document = render_manual()
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Manual generation failed: {error}", file=sys.stderr)
        return 1

    output_path = HELP_DIRECTORY / OUTPUT_FILENAME
    if arguments.check:
        if not output_path.is_file() or output_path.read_text(encoding="utf-8") != document:
            print("Manual is out of date. Run: python3 Help/generate_user_manual.py", file=sys.stderr)
            return 1
        print("Manual validation passed: 40 source pages, local resources, and internal anchors are valid.")
        return 0

    output_path.write_text(document, encoding="utf-8", newline="\n")
    print(f"Generated {output_path.name} from 40 Quick Help pages.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
