#!/usr/bin/env python3
"""Conservatively flag public/external Solidity functions with multiple successful paths.

This tool is intentionally heuristic. It is designed to support review of final
user-facing DApp entrypoints that must remain convertible into fixed circuits.
It accepts revert-only guards, but flags branches where more than one path can
finish successfully.
"""

from __future__ import annotations

import argparse
import dataclasses
import pathlib
import re
import sys
from typing import Iterable


VISIBILITY_RE = re.compile(r"\b(public|external)\b")
STATE_MUTABILITY_RE = re.compile(r"\b(view|pure)\b")
CONTRACT_RE = re.compile(r"\b(contract|abstract\s+contract)\s+([A-Za-z_][A-Za-z0-9_]*)\b")


@dataclasses.dataclass
class Issue:
    line: int
    message: str


@dataclasses.dataclass
class Summary:
    success_exits: int = 0
    continue_paths: int = 1
    issues: list[Issue] = dataclasses.field(default_factory=list)


@dataclasses.dataclass
class FunctionInfo:
    contract: str
    name: str
    line: int
    body: str
    body_start: int


class ParseError(RuntimeError):
    pass


def strip_comments(source: str) -> str:
    result: list[str] = []
    i = 0
    length = len(source)
    while i < length:
        ch = source[i]
        nxt = source[i + 1] if i + 1 < length else ""
        if ch == "/" and nxt == "/":
            while i < length and source[i] != "\n":
                result.append(" ")
                i += 1
            continue
        if ch == "/" and nxt == "*":
            result.extend("  ")
            i += 2
            while i + 1 < length and not (source[i] == "*" and source[i + 1] == "/"):
                result.append("\n" if source[i] == "\n" else " ")
                i += 1
            if i + 1 < length:
                result.extend("  ")
                i += 2
            continue
        if ch in ("'", '"'):
            quote = ch
            result.append(ch)
            i += 1
            while i < length:
                result.append(source[i])
                if source[i] == "\\" and i + 1 < length:
                    i += 2
                    if i - 1 < length:
                        result.append(source[i - 1])
                    continue
                if source[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        result.append(ch)
        i += 1
    return "".join(result)


def find_matching(source: str, start: int, open_char: str, close_char: str) -> int:
    depth = 0
    i = start
    while i < len(source):
        ch = source[i]
        if ch in ("'", '"'):
            quote = ch
            i += 1
            while i < len(source):
                if source[i] == "\\":
                    i += 2
                    continue
                if source[i] == quote:
                    break
                i += 1
        elif ch == open_char:
            depth += 1
        elif ch == close_char:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ParseError(f"unmatched {open_char}{close_char} starting at offset {start}")


def line_number(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def find_contract_bodies(source: str) -> list[tuple[str, int, int]]:
    bodies: list[tuple[str, int, int]] = []
    for match in CONTRACT_RE.finditer(source):
        brace_start = source.find("{", match.end())
        if brace_start == -1:
            continue
        brace_end = find_matching(source, brace_start, "{", "}")
        bodies.append((match.group(2), brace_start + 1, brace_end))
    return bodies


def find_functions(source: str, contract: str, body_start: int, body_end: int) -> list[FunctionInfo]:
    functions: list[FunctionInfo] = []
    i = body_start
    depth = 0
    while i < body_end:
        ch = source[i]
        if ch == "{":
            depth += 1
            i += 1
            continue
        if ch == "}":
            depth -= 1
            i += 1
            continue
        if depth == 0 and source.startswith("function", i):
            header_match = re.match(r"function\s+([A-Za-z_][A-Za-z0-9_]*)", source[i:])
            if not header_match:
                i += len("function")
                continue
            name = header_match.group(1)
            brace_start = source.find("{", i)
            semicolon = source.find(";", i)
            if brace_start == -1 or (semicolon != -1 and semicolon < brace_start):
                i = semicolon + 1 if semicolon != -1 else body_end
                continue
            header = source[i:brace_start]
            brace_end = find_matching(source, brace_start, "{", "}")
            if VISIBILITY_RE.search(header) and not STATE_MUTABILITY_RE.search(header):
                functions.append(
                    FunctionInfo(
                        contract=contract,
                        name=name,
                        line=line_number(source, i),
                        body=source[brace_start + 1 : brace_end],
                        body_start=brace_start + 1,
                    )
                )
            i = brace_end + 1
            continue
        i += 1
    return functions


class StatementParser:
    def __init__(self, body: str, body_offset: int, full_source: str) -> None:
        self.body = body
        self.pos = 0
        self.body_offset = body_offset
        self.full_source = full_source

    def skip_ws(self) -> None:
        while self.pos < len(self.body) and self.body[self.pos].isspace():
            self.pos += 1

    def eof(self) -> bool:
        self.skip_ws()
        return self.pos >= len(self.body)

    def startswith_word(self, word: str) -> bool:
        self.skip_ws()
        end = self.pos + len(word)
        if not self.body.startswith(word, self.pos):
            return False
        before_ok = self.pos == 0 or not (self.body[self.pos - 1].isalnum() or self.body[self.pos - 1] == "_")
        after_ok = end >= len(self.body) or not (self.body[end].isalnum() or self.body[end] == "_")
        return before_ok and after_ok

    def consume_word(self, word: str) -> None:
        if not self.startswith_word(word):
            raise ParseError(f"expected {word} at {self.absolute_line()}")
        self.pos += len(word)

    def absolute_line(self) -> int:
        return line_number(self.full_source, self.body_offset + self.pos)

    def parse(self) -> Summary:
        summary = Summary()
        current_continue = 1
        while not self.eof():
            stmt = self.parse_statement()
            summary.issues.extend(stmt.issues)
            summary.success_exits += current_continue * stmt.success_exits
            current_continue *= stmt.continue_paths
        summary.continue_paths = current_continue
        return summary

    def parse_statement(self) -> Summary:
        self.skip_ws()
        if self.pos >= len(self.body):
            return Summary()
        if self.body[self.pos] == "{":
            return self.parse_block()
        if self.startswith_word("if"):
            return self.parse_if()
        if self.startswith_word("for"):
            return self.parse_loop("for")
        if self.startswith_word("while"):
            return self.parse_loop("while")
        if self.startswith_word("do"):
            return self.parse_do_while()
        if self.startswith_word("unchecked"):
            self.consume_word("unchecked")
            return self.parse_statement()
        if self.startswith_word("assembly"):
            line = self.absolute_line()
            self.consume_word("assembly")
            self.skip_ws()
            if self.pos < len(self.body) and self.body[self.pos] == "{":
                _ = self.parse_block()
            return Summary(issues=[Issue(line, "contains inline assembly; review manually")])
        return self.parse_simple()

    def parse_block(self) -> Summary:
        start = self.pos
        end = find_matching(self.body, start, "{", "}")
        nested = StatementParser(self.body[start + 1 : end], self.body_offset + start + 1, self.full_source)
        self.pos = end + 1
        return nested.parse()

    def parse_parenthesized(self) -> None:
        self.skip_ws()
        if self.pos >= len(self.body) or self.body[self.pos] != "(":
            raise ParseError(f"expected ( at {self.absolute_line()}")
        end = find_matching(self.body, self.pos, "(", ")")
        self.pos = end + 1

    def parse_if(self) -> Summary:
        line = self.absolute_line()
        self.consume_word("if")
        self.parse_parenthesized()
        then_summary = self.parse_statement()
        else_summary = Summary(success_exits=0, continue_paths=1)
        if self.startswith_word("else"):
            self.consume_word("else")
            else_summary = self.parse_statement()

        summary = Summary(
            success_exits=then_summary.success_exits + else_summary.success_exits,
            continue_paths=then_summary.continue_paths + else_summary.continue_paths,
            issues=then_summary.issues + else_summary.issues,
        )
        successful_paths = summary.success_exits + summary.continue_paths
        if successful_paths > 1:
            summary.issues.append(Issue(line, f"conditional creates {successful_paths} potentially successful paths"))
        return summary

    def parse_loop(self, keyword: str) -> Summary:
        line = self.absolute_line()
        self.consume_word(keyword)
        self.parse_parenthesized()
        body_summary = self.parse_statement()
        issues = body_summary.issues.copy()
        loop_successes = body_summary.success_exits + body_summary.continue_paths
        if loop_successes > 1:
            issues.append(Issue(line, f"{keyword} loop body has multiple potentially successful paths"))
        if body_summary.success_exits > 0:
            issues.append(Issue(line, f"{keyword} loop body contains early successful termination"))
        return Summary(success_exits=0, continue_paths=1, issues=issues)

    def parse_do_while(self) -> Summary:
        line = self.absolute_line()
        self.consume_word("do")
        body_summary = self.parse_statement()
        if not self.startswith_word("while"):
            raise ParseError(f"expected while after do at {self.absolute_line()}")
        self.consume_word("while")
        self.parse_parenthesized()
        self.skip_ws()
        if self.pos < len(self.body) and self.body[self.pos] == ";":
            self.pos += 1
        issues = body_summary.issues.copy()
        loop_successes = body_summary.success_exits + body_summary.continue_paths
        if loop_successes > 1:
            issues.append(Issue(line, "do-while loop body has multiple potentially successful paths"))
        if body_summary.success_exits > 0:
            issues.append(Issue(line, "do-while loop body contains early successful termination"))
        return Summary(success_exits=0, continue_paths=1, issues=issues)

    def parse_simple(self) -> Summary:
        start = self.pos
        depth_paren = 0
        depth_bracket = 0
        while self.pos < len(self.body):
            ch = self.body[self.pos]
            if ch == "(":
                depth_paren += 1
            elif ch == ")":
                depth_paren -= 1
            elif ch == "[":
                depth_bracket += 1
            elif ch == "]":
                depth_bracket -= 1
            elif ch == ";" and depth_paren == 0 and depth_bracket == 0:
                stmt_text = self.body[start : self.pos + 1]
                self.pos += 1
                return self.classify_simple(stmt_text, line_number(self.full_source, self.body_offset + start))
            self.pos += 1
        stmt_text = self.body[start:self.pos]
        return self.classify_simple(stmt_text, line_number(self.full_source, self.body_offset + start))

    @staticmethod
    def classify_simple(stmt_text: str, line: int) -> Summary:
        stripped = stmt_text.strip()
        issues: list[Issue] = []
        if "?" in stripped and ":" in stripped:
            issues.append(Issue(line, "ternary expression may hide multiple successful paths"))
        if re.match(r"^return\b", stripped):
            return Summary(success_exits=1, continue_paths=0, issues=issues)
        if re.match(r"^revert\b", stripped):
            return Summary(success_exits=0, continue_paths=0, issues=issues)
        if re.match(r"^(break|continue)\b", stripped):
            issues.append(Issue(line, "loop control statement requires manual review"))
            return Summary(success_exits=0, continue_paths=0, issues=issues)
        return Summary(success_exits=0, continue_paths=1, issues=issues)


def load_functions(path: pathlib.Path, contract_filter: str | None, function_filter: set[str] | None) -> list[FunctionInfo]:
    source = strip_comments(path.read_text())
    selected: list[FunctionInfo] = []
    for contract_name, body_start, body_end in find_contract_bodies(source):
        if contract_filter and contract_name != contract_filter:
            continue
        for function in find_functions(source, contract_name, body_start, body_end):
            if function_filter and function.name not in function_filter:
                continue
            selected.append(function)
    return selected


def analyze_function(path: pathlib.Path, function: FunctionInfo) -> list[Issue]:
    source = strip_comments(path.read_text())
    parser = StatementParser(function.body, function.body_start, source)
    summary = parser.parse()
    issues = list(summary.issues)
    successful_paths = summary.success_exits + summary.continue_paths
    if successful_paths != 1:
        issues.append(
            Issue(function.line, f"function has {successful_paths} potentially successful paths; expected exactly 1")
        )
    return issues


def main(argv: Iterable[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("solidity_file", type=pathlib.Path)
    parser.add_argument("--contract", help="Analyze only the named contract")
    parser.add_argument("--function", action="append", dest="functions", help="Analyze only the named function")
    args = parser.parse_args(list(argv))

    functions = load_functions(args.solidity_file, args.contract, set(args.functions or []))
    if not functions:
        print("No matching public/external state-changing functions found.", file=sys.stderr)
        return 1

    failing = False
    for function in functions:
        issues = analyze_function(args.solidity_file, function)
        label = f"{function.contract}.{function.name}"
        if issues:
            failing = True
            print(f"FAIL {label} ({args.solidity_file}:{function.line})")
            for issue in issues:
                print(f"  L{issue.line}: {issue.message}")
        else:
            print(f"PASS {label} ({args.solidity_file}:{function.line})")

    return 1 if failing else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
