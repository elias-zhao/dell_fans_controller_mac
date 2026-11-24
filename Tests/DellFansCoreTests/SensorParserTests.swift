import XCTest
@testable import DellFansCore

final class SensorParserTests: XCTestCase {
    func testParseRealisticDellOutputFiltersDiscreteAndDisambiguatesDuplicates() {
        let output = """
        Inlet Temp       | 22.000     | degrees C  | ok    | na        | na        | na        | 42.000    | 47.000    | na
        Exhaust Temp     | 36.000     | degrees C  | ok    | na        | na        | na        | 70.000    | 75.000    | na
        Temp             | 45.000     | degrees C  | ok    | na        | na        | na        | 90.000    | 95.000    | na
        Temp             | 49.000     | degrees C  | nc    | na        | na        | na        | 90.000    | 95.000    | na
        Fan1             | 3600.000   | RPM        | ok    | na        | 600.000   | na        | na        | na        | na
        Fan2             | 3720.000   | RPM        | ok    | na        | 600.000   | na        | na        | na        | na
        Fan3             | 0.000      | RPM        | cr    | na        | 600.000   | na        | na        | na        | na
        Current 1        | 0.800      | Amps       | ok    | na        | na        | na        | na        | na        | na
        Voltage 1        | 228.000    | Volts      | ok    | na        | na        | na        | na        | na        | na
        Pwr Consumption  | 168.000    | Watts      | ok    | na        | na        | na        | 800.000   | 900.000   | na
        Status           | 0x00       | discrete   | 0x0000| na        | na        | na        | na        | na        | na
        Presence         | 0x01       | discrete   | 0x0100| na        | na        | na        | na        | na        | na
        Intrusion        | 0x00       | discrete   | 0x0000| na        | na        | na        | na        | na        | na
        Watchdog         | 0x00       | discrete   | 0x0000| na        | na        | na        | na        | na        | na
        ECC Corr Err     | 0x00       | discrete   | 0x0000| na        | na        | na        | na        | na        | na

        malformed line without pipes
        a | b | c
        """

        let readings = SensorParser.parse(output)

        XCTAssertEqual(readings.count, 10)

        let inlet = readings[0]
        XCTAssertEqual(inlet.id, "0-Inlet Temp")
        XCTAssertEqual(inlet.name, "Inlet Temp")
        XCTAssertEqual(inlet.displayName, "Inlet Temp")
        XCTAssertEqual(inlet.numericValue, 22.0)
        XCTAssertEqual(inlet.unit, "°C")
        XCTAssertEqual(inlet.category, .temperature)
        XCTAssertEqual(inlet.status, .ok)
        XCTAssertEqual(inlet.upperNonCritical, 42.0)
        XCTAssertEqual(inlet.upperCritical, 47.0)

        let cpu1 = readings[2]
        XCTAssertEqual(cpu1.id, "2-Temp")
        XCTAssertEqual(cpu1.name, "Temp")
        XCTAssertEqual(cpu1.displayName, "Temp #1")
        XCTAssertEqual(cpu1.numericValue, 45.0)
        XCTAssertEqual(cpu1.status, .ok)

        let cpu2 = readings[3]
        XCTAssertEqual(cpu2.id, "3-Temp")
        XCTAssertEqual(cpu2.name, "Temp")
        XCTAssertEqual(cpu2.displayName, "Temp #2")
        XCTAssertEqual(cpu2.numericValue, 49.0)
        XCTAssertEqual(cpu2.status, .nonCritical)

        XCTAssertEqual(readings[4].category, .fan)
        XCTAssertEqual(readings[4].unit, "RPM")
        XCTAssertEqual(readings[6].status, .critical)
        XCTAssertEqual(readings[7].category, .current)
        XCTAssertEqual(readings[7].unit, "A")
        XCTAssertEqual(readings[8].category, .voltage)
        XCTAssertEqual(readings[8].unit, "V")
        XCTAssertEqual(readings[9].category, .power)
        XCTAssertEqual(readings[9].unit, "W")

        let summary = SensorParser.summarize(readings)
        XCTAssertEqual(summary.inletTemperature, 22.0)
        XCTAssertEqual(summary.exhaustTemperature, 36.0)
        XCTAssertEqual(summary.highestTemperature, 49.0)
        XCTAssertEqual(summary.cpuTemperatures.map(\.label), ["CPU1", "CPU2"])
        XCTAssertEqual(summary.cpuTemperatures.map(\.value), [45.0, 49.0])
        XCTAssertEqual(summary.fanRPMs.count, 3)
        XCTAssertEqual(summary.averageFanRPM, 3660)
        XCTAssertEqual(summary.powerWatts, 168.0)
        XCTAssertEqual(summary.menuBarTemperatureText, "49°C")
    }

    func testParseStatusVariantsAndNonNumericValues() {
        let output = """
        CPU1 Temp | 52.4 | C | lnc | na | na | na | na | na | na
        CPU2 Temp | na | degrees C | ns | na | na | na | na | na | na
        Vcore | 1.12 | unspecified | ucr | na | na | na | na | na | na
        PS1 Current | 2.5 | unspecified | lnr | na | na | na | na | na | na
        System Power | 210 | unspecified | unknown_code | na | na | na | na | na | na
        """

        let readings = SensorParser.parse(output)
        XCTAssertEqual(readings.count, 5)
        XCTAssertEqual(readings[0].status, .nonCritical)
        XCTAssertEqual(readings[0].unit, "°C")
        XCTAssertEqual(readings[1].status, .notAvailable)
        XCTAssertNil(readings[1].numericValue)
        XCTAssertEqual(readings[2].category, .voltage)
        XCTAssertEqual(readings[2].status, .critical)
        XCTAssertEqual(readings[3].category, .current)
        XCTAssertEqual(readings[3].status, .nonRecoverable)
        XCTAssertEqual(readings[4].category, .power)
        XCTAssertEqual(readings[4].status, .unknown)

        let summary = SensorParser.summarize(readings)
        XCTAssertEqual(summary.cpuTemperatures.count, 1)
        XCTAssertEqual(summary.cpuTemperatures[0].label, "CPU1 Temp")
        XCTAssertEqual(summary.menuBarTemperatureText, "52°C")
        XCTAssertNil(summary.averageFanRPM)
    }

    func testSummarizeEmptyAndFallbackHighestTemperature() {
        XCTAssertEqual(SensorParser.summarize([]), .empty)

        let output = "Ambient Temp | 29.6 | degrees C | ok | na | na | na | na | na | na"
        let readings = SensorParser.parse(output)
        let summary = SensorParser.summarize(readings)

        XCTAssertTrue(summary.cpuTemperatures.isEmpty)
        XCTAssertEqual(summary.highestTemperature, 29.6)
        XCTAssertEqual(summary.menuBarTemperatureText, "30°C")
    }
}
