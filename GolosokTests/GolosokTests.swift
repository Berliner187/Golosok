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

    @Test func timeOfDayBucketsByHour() {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        let cal = Calendar.current
        func dated(_ hour: Int) -> String {
            let d = cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
            return formatter.string(from: d)
        }
        let items = [
            TranscriptionItem(date: dated(7), text: "а", duration: "5.0 сек"),
            TranscriptionItem(date: dated(14), text: "б", duration: "5.0 сек"),
            TranscriptionItem(date: dated(21), text: "в", duration: "5.0 сек"),
            TranscriptionItem(date: dated(2), text: "г", duration: "5.0 сек")
        ]
        let stats = DashboardCalculator.calculate(from: items, range: .all)
        #expect(stats.timeOfDay.map(\.count) == [1, 1, 1, 1])
    }

    @Test func sizeHistogramBucketsChars() {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        let now = formatter.string(from: Date())
        let items = [
            TranscriptionItem(date: now, text: String(repeating: "а", count: 50), duration: "5.0 сек"),
            TranscriptionItem(date: now, text: String(repeating: "б", count: 500), duration: "5.0 сек")
        ]
        let stats = DashboardCalculator.calculate(from: items, range: .all)
        #expect(stats.sizeHistogram[0].count == 1)
        #expect(stats.sizeHistogram[2].count == 1)
    }

    @Test func rangeFiltersOldNotes() {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        let cal = Calendar.current
        let today = formatter.string(from: Date())
        let oldDay = cal.date(byAdding: .day, value: -10, to: Date())!
        let old = formatter.string(from: oldDay)
        let items = [
            TranscriptionItem(date: today, text: "сегодня", duration: "5.0 сек"),
            TranscriptionItem(date: old, text: "старое", duration: "5.0 сек")
        ]
        let week = DashboardCalculator.calculate(from: items, range: .week)
        let all = DashboardCalculator.calculate(from: items, range: .all)
        #expect(week.sizeHistogram.reduce(0) { $0 + $1.count } == 1)
        #expect(all.sizeHistogram.reduce(0) { $0 + $1.count } == 2)
        #expect(week.weekdayAggregate.reduce(0) { $0 + $1.count } == 1)
    }

    @Test func activityCountsTheRightDay() {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let items = [
            TranscriptionItem(date: formatter.string(from: noon), text: "а", duration: "5.0 сек"),
            TranscriptionItem(date: formatter.string(from: noon.addingTimeInterval(3600)), text: "б", duration: "5.0 сек")
        ]
        let stats = DashboardCalculator.calculate(from: items, range: .all)
        let day = cal.startOfDay(for: noon)
        let cell = stats.activity.first { $0.date == day }
        #expect(cell?.count == 2)
    }

    @Test func levelProgressTargetsNextThreshold() {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        let now = formatter.string(from: Date())
        let items = (0..<5).map { _ in TranscriptionItem(date: now, text: "а", duration: "5.0 сек") }
        let stats = DashboardCalculator.calculate(from: items)
        #expect(stats.levelProgress.nextThreshold == 6)
        #expect(stats.levelProgress.isMaxed == false)
    }

    @Test func activityWindowMatchesSelectedRange() {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        let items = [TranscriptionItem(date: formatter.string(from: Date()), text: "а", duration: "5.0 сек")]
        let stats = DashboardCalculator.calculate(from: items, range: .all)
        #expect(stats.activity.count == 84)
        let week = DashboardCalculator.calculate(from: items, range: .week)
        #expect(week.activity.count == 7)
    }

    // MARK: - Synced word alignment

    private func timedWords(_ texts: [String]) -> [TimedWord] {
        texts.enumerated().map { TimedWord(text: $0.element, start: Double($0.offset), end: Double($0.offset) + 1) }
    }

    private func wordRanges(_ text: String, _ words: [TimedWord]) -> [NSRange] {
        SyncedTextView.Coordinator(onSeek: { _ in }).wordRanges(text: text, words: words)
    }

    @Test func exactWordsProducePositionalRanges() {
        let text = "Привет! Это проверка."
        let words = timedWords(["Привет!", "Это", "проверка."])
        let ranges = wordRanges(text, words)
        #expect(ranges.count == 3)
        #expect(ranges[0] == NSRange(location: 0, length: 7))
        #expect(ranges[1] == NSRange(location: 8, length: 3))
        #expect(ranges[2] == NSRange(location: 12, length: 9))
    }

    @Test func caseInsensitiveTokensStillAlign() {
        let text = "Привет мир"
        let words = timedWords(["привет", "мир"])
        let ranges = wordRanges(text, words)
        #expect(ranges[0].location == 0)
        #expect(ranges[1].location == 7)
    }

    @Test func extraTextWordIsSkippedByAlignment() {
        let text = "один два три"
        let words = timedWords(["один", "три"])
        let ranges = wordRanges(text, words)
        #expect(ranges[0] == NSRange(location: 0, length: 4))
        #expect(ranges[1] == NSRange(location: 9, length: 3))
    }

    @Test func missingWordBecomesNotFoundPlaceholder() {
        let text = "привет мир"
        let words = timedWords(["привет", "неттакого", "мир"])
        let ranges = wordRanges(text, words)
        #expect(ranges.count == 3)
        #expect(ranges[0] == NSRange(location: 0, length: 6))
        #expect(ranges[1].location == NSNotFound)
        #expect(ranges[2] == NSRange(location: 7, length: 3))
    }

    @Test func punctuationAttachedToTokensStillAligns() {
        let text = "Числа 1, 2, 3 и всё."
        let words = timedWords(["Числа", "1,", "2,", "3", "и", "всё."])
        let ranges = wordRanges(text, words)
        #expect(ranges.allSatisfy { $0.location != NSNotFound })
        #expect(ranges.count == 6)
    }

    @Test func emptyWordsProduceNoRanges() {
        #expect(wordRanges("", timedWords(["слово"])).isEmpty)
        #expect(wordRanges("текст", []).isEmpty)
    }

    // MARK: - Whisper timing interpolation

    @Test func interpolateTimingsSpreadsAcrossRange() {
        let words = timedWords(["а", "б", "в"])
        let result = AudioCapture.interpolateTimings(words, from: 1.0, to: 4.0)
        #expect(result.count == 3)
        #expect(result[0].start == 1.0)
        #expect(result[2].end <= 4.001)
        for i in 1..<result.count {
            #expect(result[i].start >= result[i - 1].end)
            #expect(result[i].end > result[i].start)
        }
    }

    @Test func interpolateTimingsPreservesOrder() {
        let words = timedWords(["один", "два", "три"])
        let result = AudioCapture.interpolateTimings(words, from: 0, to: 3.0)
        #expect(result.map(\.text) == ["один", "два", "три"])
        #expect(result[0].start == 0)
        #expect(result.last?.end == 3.0)
    }

    // MARK: - Whisper ms→s migration

    @Test func millisecondTimingsAreConvertedToSeconds() {
        let words = [TimedWord(text: "Привет", start: 0, end: 7650.5), TimedWord(text: "мир", start: 7650.5, end: 8000)]
        let result = AudioCapture.normalizedWords(words, duration: 7.6)
        #expect(result[0].end == 7.6505)
        #expect(result[1].start == 7.6505)
    }

    @Test func secondTimingsStayUntouched() {
        let words = [TimedWord(text: "Так,", start: 0.76, end: 1.04), TimedWord(text: "звук", start: 1.2, end: 1.48)]
        let result = AudioCapture.normalizedWords(words, duration: 6.6)
        #expect(result == words)
    }
}
