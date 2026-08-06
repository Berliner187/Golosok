//
//  GolosokTests.swift
//  GolosokTests
//
//  Created by kozak_dev on 26.07.2026.
//

import Testing
import Foundation
@testable import Golosok

struct GolosokTests {

    // MARK: - TextFormatter

    @Test func emptyTextStaysEmpty() {
        #expect(TextFormatter.formatIntoParagraphs("") == "")
    }

    @Test func plainTextWithoutPunctuationIsUntouched() {
        #expect(TextFormatter.formatIntoParagraphs("просто строка") == "просто строка")
    }

    @Test func sentencesJoinIntoSingleParagraph() {
        let result = TextFormatter.formatIntoParagraphs("Привет. Как дела? Хорошо!")
        #expect(result == "Привет. Как дела? Хорошо!")
    }

    @Test func paragraphBreaksAfterThreeSentences() {
        let result = TextFormatter.formatIntoParagraphs("Первое. Второе. Третье. Четвертое.")
        #expect(result == "Первое. Второе. Третье.\n\nЧетвертое.")
    }

    @Test func dialogueLinesGetOwnParagraphs() {
        let result = TextFormatter.formatIntoParagraphs("— Привет. — Здравствуй!")
        #expect(result == "— Привет.\n\n— Здравствуй!")
    }

    // MARK: - DashboardCalculator

    @Test func emptyHistoryProducesZeroedStats() {
        let stats = DashboardCalculator.calculate(from: [])
        #expect(stats.totalNotes == 0)
        #expect(stats.hoursSaved == "0.00")
        #expect(stats.levelName == "НОВИЧОК")
        #expect(stats.wpm == 0)
    }

    @Test func historyStatsAreAggregated() {
        let items = [
            TranscriptionItem(date: "05.08.2026, 10:00", text: "Привет как дела", duration: "10.5 сек", speedup: 12.0),
            TranscriptionItem(date: "05.08.2026, 11:00", text: "Второй текст", duration: "2.0 мин", speedup: 8.0)
        ]
        let stats = DashboardCalculator.calculate(from: items)
        #expect(stats.totalNotes == 2)
        #expect(stats.totalMinutes == "2.2")
        #expect(stats.wpm == 130)
    }

    @Test func weeklyTrendCountsAllNotes() {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        var mondayComp = DateComponents()
        mondayComp.weekday = 2
        mondayComp.weekOfYear = comps.weekOfYear
        mondayComp.yearForWeekOfYear = comps.yearForWeekOfYear
        let monday = calendar.date(from: mondayComp)!
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"

        let items = [
            TranscriptionItem(date: formatter.string(from: monday), text: "Один", duration: "5.0 сек"),
            TranscriptionItem(date: formatter.string(from: monday), text: "Два", duration: "5.0 сек"),
            TranscriptionItem(date: formatter.string(from: tuesday), text: "Три", duration: "5.0 сек")
        ]
        let stats = DashboardCalculator.calculate(from: items)
        let totalCounted = stats.weeklyTrend.reduce(0) { $0 + $1.count }
        let totalChars = stats.weeklyTrend.reduce(0) { $0 + $1.chars }
        #expect(totalCounted == 3)
        #expect(totalChars == 10)
    }
}
