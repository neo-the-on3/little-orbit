#!/usr/bin/env python3
"""Write a pull-request test summary from JUnit XML and xcresult bundles.

Reads test-results/*.xml (Swift PM --xunit-output) and test-results/*.xcresult
(xcodebuild -resultBundlePath). Appends Markdown to GITHUB_STEP_SUMMARY when
that variable is set, and always prints the same Markdown on stdout.

No third-party actions and no extra workflow permissions. xcresult bundles are
read with xcrun xcresulttool, which ships with Xcode.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "directory",
        type=Path,
        help="Directory that contains JUnit XML files and xcresult bundles",
    )
    parser.add_argument(
        "--require",
        action="store_true",
        help="Exit 1 unless the directory contains at least one reported test",
    )
    args = parser.parse_args()

    directory: Path = args.directory
    lines: list[str] = ["## Test results", ""]
    xml_files = sorted(directory.glob("*.xml")) if directory.is_dir() else []
    empty_swift_testing = [path for path in xml_files if swift_testing_report_is_empty(path)]
    junit_files = [path for path in xml_files if path not in empty_swift_testing]
    bundles = sorted(path for path in directory.glob("*.xcresult") if path.is_dir()) if directory.is_dir() else []

    junit_cases = 0
    for report in junit_files:
        section, count = junit_section(report)
        lines.extend(section)
        junit_cases += count

    xcresult_cases = 0
    xcresult_error = False
    for bundle in bundles:
        section, count, failed = xcresult_section(bundle)
        lines.extend(section)
        xcresult_cases += count
        xcresult_error = xcresult_error or failed

    if not junit_files and not bundles:
        if empty_swift_testing:
            lines.append(
                "Only empty Swift Testing xUnit files were produced, so XCTest results were not recorded."
            )
        else:
            lines.append("No JUnit or xcresult reports were produced.")
        lines.append("")

    visible = junit_cases + xcresult_cases
    publish("\n".join(lines).rstrip() + "\n")

    if xcresult_error:
        print("error: xcresulttool could not read a result bundle.", file=sys.stderr)
        return 1
    if args.require and visible == 0:
        print(
            "error: CI produced no visible test cases. "
            "An empty Swift Testing xUnit file does not count.",
            file=sys.stderr,
        )
        return 1
    if (junit_files or bundles) and visible == 0:
        print("error: test reports contain no test cases.", file=sys.stderr)
        return 1
    return 0


def swift_testing_report_is_empty(path: Path) -> bool:
    """True for the empty *-swift-testing.xml Swift 6.4 writes beside XCTest XML."""
    if not path.name.endswith("-swift-testing.xml"):
        return False
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return False
    return not any(True for _ in root.iter("testcase"))


def junit_section(report: Path) -> tuple[list[str], int]:
    try:
        root = ET.parse(report).getroot()
    except ET.ParseError as error:
        return [f"### JUnit `{report.as_posix()}`", "", f"Could not parse XML: {error}", ""], 0

    suites = list(root.iter("testsuite"))
    cases = [case for suite in suites for case in suite.findall("testcase")]
    failures = [case for case in cases if case.find("failure") is not None or case.find("error") is not None]
    skipped = [case for case in cases if case.find("skipped") is not None]

    lines = [
        f"### JUnit `{report.as_posix()}`",
        "",
        "| Tests | Failures | Skipped |",
        "| --- | --- | --- |",
        f"| {len(cases)} | {len(failures)} | {len(skipped)} |",
        "",
    ]
    if failures:
        lines.append("Failed tests:")
        lines.append("")
        for case in failures:
            name = f"{text(case.get('classname'))}.{text(case.get('name'))}"
            messages = []
            for child in list(case.findall("failure")) + list(case.findall("error")):
                message = text(child.get("message")) or text(child.text)
                if message:
                    messages.append(message.replace("\n", " "))
            detail = cell(" ".join(messages)) if messages else "failed"
            lines.append(f"- `{cell(name)}`: {detail}")
        lines.append("")

    lines.append("<details>")
    lines.append(f"<summary>{len(cases)} test cases</summary>")
    lines.append("")
    lines.append("| Class | Test | Result |")
    lines.append("| --- | --- | --- |")
    for case in cases:
        if case.find("failure") is not None or case.find("error") is not None:
            result = "Failed"
        elif case.find("skipped") is not None:
            result = "Skipped"
        else:
            result = "Passed"
        lines.append(
            f"| {cell(text(case.get('classname')))} | {cell(text(case.get('name')))} | {result} |"
        )
    lines.extend(["", "</details>", ""])
    return lines, len(cases)


def xcresult_section(bundle: Path) -> tuple[list[str], int, bool]:
    lines = [f"### xcresult `{bundle.as_posix()}`", ""]
    summary_cmd = [
        "xcrun",
        "xcresulttool",
        "get",
        "test-results",
        "summary",
        "--path",
        str(bundle),
    ]
    completed = subprocess.run(summary_cmd, capture_output=True, text=True)
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "xcresulttool failed").strip()
        lines.extend(["`xcresulttool` could not read this bundle:", "", "```", detail, "```", ""])
        return lines, 0, True

    try:
        summary = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        lines.extend([f"Could not parse xcresult summary JSON: {error}", ""])
        return lines, 0, True

    total = int(summary.get("totalTestCount") or 0)
    failed = int(summary.get("failedTests") or 0)
    skipped = int(summary.get("skippedTests") or 0)
    passed = int(summary.get("passedTests") or 0)
    result = text(summary.get("result")) or "unknown"
    lines.extend(
        [
            "| Result | Tests | Passed | Failed | Skipped |",
            "| --- | --- | --- | --- | --- |",
            f"| {cell(result)} | {total} | {passed} | {failed} | {skipped} |",
            "",
        ]
    )
    failure_rows = summary.get("testFailures") or []
    if failure_rows:
        lines.append("Failed tests:")
        lines.append("")
        for failure in failure_rows:
            name = text(failure.get("testName")) or text(failure.get("testIdentifierString"))
            target = text(failure.get("targetName"))
            label = f"{target}.{name}" if target else name
            lines.append(f"- `{cell(label)}`: {cell(text(failure.get('failureText')))}")
        lines.append("")

    tests_cmd = [
        "xcrun",
        "xcresulttool",
        "get",
        "test-results",
        "tests",
        "--path",
        str(bundle),
    ]
    tests = subprocess.run(tests_cmd, capture_output=True, text=True)
    cases: list[tuple[str, str]] = []
    if tests.returncode == 0:
        try:
            payload = json.loads(tests.stdout)
        except json.JSONDecodeError:
            payload = {}
        for node in walk(payload.get("testNodes") or []):
            if node.get("nodeType") == "Test Case":
                cases.append((text(node.get("nodeIdentifier")) or text(node.get("name")), text(node.get("result"))))

    if cases:
        shown = cases[:100]
        lines.append("<details>")
        lines.append(f"<summary>{len(cases)} test cases</summary>")
        lines.append("")
        lines.append("| Test | Result |")
        lines.append("| --- | --- |")
        for name, case_result in shown:
            lines.append(f"| {cell(name)} | {cell(case_result)} |")
        if len(cases) > len(shown):
            lines.append(f"| … | {len(cases) - len(shown)} more in the artifact |")
        lines.extend(["", "</details>", ""])
    return lines, total, False


def walk(nodes: object):
    if not isinstance(nodes, list):
        return
    for node in nodes:
        if not isinstance(node, dict):
            continue
        yield node
        yield from walk(node.get("children"))


def publish(markdown: str) -> None:
    sys.stdout.write(markdown)
    sys.stdout.flush()
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary:
        return
    with open(summary, "a", encoding="utf-8") as handle:
        handle.write(markdown)


def text(value: object) -> str:
    if value is None:
        return ""
    return str(value).strip()


def cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


if __name__ == "__main__":
    sys.exit(main())
