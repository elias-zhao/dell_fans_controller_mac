import XCTest
@testable import DellFansCore

final class FirmwareCheckTests: XCTestCase {
    func testParseMCInfoIDRAC8Supported() {
        let mcOutput = """
        Device ID                 : 32
        Device Revision           : 1
        Firmware Revision         : 2.75
        IPMI Version              : 2.0
        Manufacturer ID           : 674
        Manufacturer Name         : DELL Inc
        Product ID                : 256 (0x0100)
        Aux Firmware Rev Info     :
            0x00
            0x00
            0x00
            0x00
        """

        let info = FirmwareCheck.parseMCInfo(mcOutput, serverModel: "R730")
        XCTAssertEqual(info.firmwareRevision, "2.75")
        XCTAssertEqual(info.rawFirmwareRevision, "2.75")
        XCTAssertEqual(info.manufacturerID, 674)
        XCTAssertEqual(info.manufacturerName, "DELL Inc")
        XCTAssertEqual(info.productID, 256)
        XCTAssertEqual(info.serverModel, "R730")
        XCTAssertTrue(info.supportStatus.isSupported)
    }

    func testParseMCInfoIDRAC9_330SupportedWithAuxRevision() {
        let mcOutput = """
        Firmware Revision         : 3.30
        Manufacturer ID           : 674
        Manufacturer Name         : DELL Inc
        Product ID                : 256 (0x0100)
        Aux Firmware Rev Info     :
            0x1e
            0x1e
            0x00
            0x00
        """

        let info = FirmwareCheck.parseMCInfo(mcOutput)
        XCTAssertEqual(info.rawFirmwareRevision, "3.30")
        XCTAssertEqual(info.firmwareRevision, "3.30.30.30")
        XCTAssertEqual(info.auxFirmwareRevision, "0x1e 0x1e 0x00 0x00")
        XCTAssertTrue(info.supportStatus.isSupported)
    }

    func testParseMCInfoIDRAC9_334Unsupported() {
        let mcOutput = """
        Firmware Revision         : 3.34
        Manufacturer ID           : 674
        Manufacturer Name         : DELL Inc
        Aux Firmware Rev Info     :
            0x22
            0x22
            0x00
            0x00
        """

        let info = FirmwareCheck.parseMCInfo(mcOutput)
        XCTAssertEqual(info.firmwareRevision, "3.34.34.34")
        XCTAssertTrue(info.supportStatus.isUnsupported)
    }

    func testEvaluateSupportEdgeCases() {
        let warningBoundary = FirmwareCheck.evaluateSupport(
            firmwareRevision: "3.32.32.32",
            auxRevision: nil,
            manufacturerID: 674,
            manufacturerName: "DELL Inc"
        )
        if case .warning = warningBoundary {
        } else {
            XCTFail("Expected warning for 3.32.32.32, got \(warningBoundary)")
        }

        let idrac10 = FirmwareCheck.evaluateSupport(
            firmwareRevision: "4.00.00.00",
            auxRevision: nil,
            manufacturerID: 674,
            manufacturerName: "DELL Inc"
        )
        XCTAssertTrue(idrac10.isUnsupported)

        let nonDell = FirmwareCheck.evaluateSupport(
            firmwareRevision: "2.10",
            auxRevision: nil,
            manufacturerID: 47488,
            manufacturerName: "Supermicro"
        )
        if case .warning(let reason) = nonDell {
            XCTAssertTrue(reason.contains("Supermicro"))
        } else {
            XCTFail("Expected warning for non-Dell vendor, got \(nonDell)")
        }

        let unknown = FirmwareCheck.evaluateSupport(
            firmwareRevision: "invalid",
            auxRevision: nil,
            manufacturerID: 674,
            manufacturerName: "DELL Inc"
        )
        if case .unknown = unknown {
        } else {
            XCTFail("Expected unknown for unparseable revision, got \(unknown)")
        }
    }

    func testParseServerModelFromFRU() {
        let fruProduct = """
        Chassis Type          : Rack Mount Chassis
        Board Mfg             : DELL
        Board Product         : 0WCJNT
        Product Manufacturer  : DELL
        Product Name          : PowerEdge R730
        """
        XCTAssertEqual(FirmwareCheck.parseServerModel(fromFRU: fruProduct), "R730")

        let fruBoardFallback = """
        Board Product         : PowerEdge T630
        Product Name          : Unspecified
        """
        XCTAssertEqual(FirmwareCheck.parseServerModel(fromFRU: fruBoardFallback), "T630")

        XCTAssertNil(FirmwareCheck.parseServerModel(fromFRU: "Product Name : N/A"))
    }
}
