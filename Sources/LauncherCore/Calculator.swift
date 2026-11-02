// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public enum Calculator {
    /// The value of `input` when it is arithmetic with at least one binary operator; otherwise nil.
    /// Operators: + - * / and x (multiply). Parentheses, decimals, leading minus.
    public static func evaluate(_ input: String) -> Double? {
        guard let tokens = tokenize(input) else { return nil }
        var p = Parser(tokens: tokens)
        guard p.hasBinaryOperator, let v = p.parseExpression(), p.atEnd, v.isFinite else { return nil }
        return v
    }

    enum Token: Equatable { case number(Double), op(Character), lparen, rparen }

    static func tokenize(_ s: String) -> [Token]? {
        var out: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c.isWhitespace { i = s.index(after: i); continue }
            if (c.isASCII && c.isNumber) || c == "." {
                var j = i
                while j < s.endIndex, (s[j].isASCII && s[j].isNumber) || s[j] == "." || s[j] == "," {
                    j = s.index(after: j)
                }
                guard let v = NumberText.value(of: String(s[i..<j])) else { return nil }
                out.append(.number(v)); i = j; continue
            }
            switch c {
            case "+", "-", "*", "/": out.append(.op(c))
            case "x", "X": out.append(.op("*"))
            case "(": out.append(.lparen)
            case ")": out.append(.rparen)
            default: return nil
            }
            i = s.index(after: i)
        }
        return out
    }

    struct Parser {
        let tokens: [Token]
        var pos = 0

        var atEnd: Bool { pos == tokens.count }

        /// An operator that follows a number or ")" — so "-42" alone is not a calculation.
        var hasBinaryOperator: Bool {
            tokens.indices.dropFirst().contains { i in
                guard case .op = tokens[i] else { return false }
                switch tokens[i - 1] { case .number, .rparen: return true; default: return false }
            }
        }

        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while let op = peekOp("+-") {
                pos += 1
                guard let rhs = parseTerm() else { return nil }
                lhs = op == "+" ? lhs + rhs : lhs - rhs
            }
            return lhs
        }

        mutating func parseTerm() -> Double? {
            guard var lhs = parseFactor() else { return nil }
            while let op = peekOp("*/") {
                pos += 1
                guard let rhs = parseFactor() else { return nil }
                if op == "/" {
                    guard rhs != 0 else { return nil }
                    lhs /= rhs
                } else {
                    lhs *= rhs
                }
            }
            return lhs
        }

        mutating func parseFactor() -> Double? {
            guard pos < tokens.count else { return nil }
            switch tokens[pos] {
            case .op("-"): pos += 1; return parseFactor().map { -$0 }
            case .op("+"): pos += 1; return parseFactor()
            case .number(let v): pos += 1; return v
            case .lparen:
                pos += 1
                guard let v = parseExpression(), pos < tokens.count, tokens[pos] == .rparen else { return nil }
                pos += 1
                return v
            default: return nil
            }
        }

        func peekOp(_ set: String) -> Character? {
            guard pos < tokens.count, case .op(let c) = tokens[pos], set.contains(c) else { return nil }
            return c
        }
    }
}
