import XCTest
@testable import HunterFilesCore

final class GenerationResponseTests: XCTestCase {
    func testMetadataAndCitationValidation() throws {
        let metadata = try GeneratedMetadata.parse("```json\n{\"name\":\"海洋/珊瑚\",\"summary\":\"海底的鱼类。\"}\n```")
        XCTAssertEqual(metadata.name, "海洋_珊瑚")
        XCTAssertThrowsError(try GeneratedMetadata.parse("{\"name\":\"\",\"summary\":\"描述\"}"))
        XCTAssertThrowsError(try GeneratedMetadata.parse("{\"name\":\"标题\",\"summary\":42}"))
        XCTAssertThrowsError(try GroundedAnswer.parse("{\"answer\":\"错误来源[2]\",\"sources\":[2]}", sourceCount: 1))
        XCTAssertThrowsError(try GroundedAnswer.parse("{\"answer\":\"伪造来源[9]\",\"sources\":[1]}", sourceCount: 2))
        let answer = try GroundedAnswer.parse("{\"answer\":\"存在鱼类[1]\",\"sources\":[1,1]}", sourceCount: 1)
        XCTAssertEqual(answer.sources, [1])
        let missing = try GroundedAnswer.parse("{\"answer\":\"没有根据的说法\",\"sources\":[]}", sourceCount: 0)
        XCTAssertTrue(missing.answer.contains("不足以回答"))
    }
}
