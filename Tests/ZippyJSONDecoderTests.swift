//Copyright (c) 2018 Michael Eisel. All rights reserved.

import XCTest
import ZippyJSON

struct TestCodingKey: CodingKey {
    var stringValue: String

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    var intValue: Int? {
        return nil
    }

    init?(intValue: Int) {
        return nil
    }
}

extension DecodingError: Equatable {
    public static func == (lhs: DecodingError, rhs: DecodingError) -> Bool {
        switch lhs {
        case .typeMismatch(let lType, let lContext):
            if case let DecodingError.typeMismatch(rType, rContext) = rhs {
                return lType == rType && rContext == lContext
            }
        case .valueNotFound(let lType, let lContext):
            if case let DecodingError.valueNotFound(rType, rContext) = rhs {
                return lType == rType && rContext == lContext
            }
        case .keyNotFound(let lKey, let lContext):
            if case let DecodingError.keyNotFound(rKey, rContext) = rhs {
                return keysEqual(lKey, rKey) && rContext == lContext
            }
        case .dataCorrupted(let lContext):
            if case let DecodingError.dataCorrupted(rContext) = rhs {
                return rContext == lContext
            }
        @unknown default:
            return false
        }
        return false
    }
}

func keysEqual(_ lhs: CodingKey, _ rhs: CodingKey) -> Bool {
    return lhs.stringValue == rhs.stringValue || (lhs.intValue != nil && lhs.intValue == rhs.intValue)
}

public func testRoundTrip<T: Codable & Equatable>(_ object: T) {
    let data: Data = try! JSONEncoder().encode(object)
    let json = String(data: data, encoding: .utf8)!
    testRoundTrip(of: T.self, json: json)
}

func threadTime() -> CFTimeInterval {
    var tp: timespec = timespec()
    if #available(macOS 10.12, *) {
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &tp)
    } else {
        abort()
    }
    return Double(tp.tv_sec) + Double(tp.tv_nsec) / 1e9;
}

func time(_ closure: () -> ()) -> CFTimeInterval {
    let start = threadTime()
    //let _: Int = autoreleasepool {
        closure()
        //return 0
    //}
    let end = threadTime()
    return end - start
}

func averageTime(_ closure: () -> ()) -> CFTimeInterval {
    let count = 10
    var times: [CFTimeInterval] = []
    for _ in 0..<count {
        times.append(time(closure))
    }
    return times.dropFirst(count / 3).reduce(0, +) / CFTimeInterval(times.count)
}

func testPerf<T: Decodable>(appleDecoder: JSONDecoder, zippyDecoder: ZippyJSONDecoder, json: Data, type: T.Type) {
    let zippyTime = averageTime {
        let _ = try! zippyDecoder.decode(type, from: json)
    }
    let appleTime = averageTime {
        let _ = try! appleDecoder.decode(type, from: json)
    }
    XCTAssert(zippyTime < appleTime / 3)
}

public func testRoundTrip<T>(of value: T.Type,
                              json: String,
                              outputFormatting: JSONEncoder.OutputFormatting = [],
                              dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .deferredToDate,
                              dateDecodingStrategy: ZippyJSONDecoder.DateDecodingStrategy = .deferredToDate,
                              dataEncodingStrategy: JSONEncoder.DataEncodingStrategy = .base64,
                              dataDecodingStrategy: ZippyJSONDecoder.DataDecodingStrategy = .base64,
                              keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys,
                              keyDecodingStrategy: ZippyJSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
                              nonConformingFloatEncodingStrategy: JSONEncoder.NonConformingFloatEncodingStrategy = .throw,
                              nonConformingFloatDecodingStrategy: ZippyJSONDecoder.NonConformingFloatDecodingStrategy = .throw,
                              testPerformance: Bool = false) where T : Decodable, T : Equatable {
    do {
        
        let d = JSONDecoder()
        d.dateDecodingStrategy = ZippyJSONDecoder.convertDateDecodingStrategy(dateDecodingStrategy)
        d.dataDecodingStrategy = ZippyJSONDecoder.convertDataDecodingStrategy(dataDecodingStrategy)
        d.nonConformingFloatDecodingStrategy = ZippyJSONDecoder.convertNonConformingFloatDecodingStrategy(nonConformingFloatDecodingStrategy)
        d.keyDecodingStrategy = ZippyJSONDecoder.convertKeyDecodingStrategy(keyDecodingStrategy)
        let apple = try d.decode(T.self, from: json.data(using: .utf8)!)
        
        let decoder = ZippyJSONDecoder()
        decoder.dateDecodingStrategy = dateDecodingStrategy
        decoder.dataDecodingStrategy = dataDecodingStrategy
        decoder.nonConformingFloatDecodingStrategy = nonConformingFloatDecodingStrategy
        decoder.keyDecodingStrategy = keyDecodingStrategy
        let decoded = try decoder.decode(T.self, from: json.data(using: .utf8)!)
        
        XCTAssertEqual(decoded, apple)
        if decoded == apple && testPerformance {
            testPerf(appleDecoder: d, zippyDecoder: decoder, json: json.data(using: .utf8)!, type: T.self)
        }
    } catch {
        XCTFail("Failed to decode \(T.self) from JSON: \(error)")
    }
}

fileprivate struct JSONKey : CodingKey {
    public var stringValue: String
    public var intValue: Int?

    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    public init(stringValue: String, intValue: Int?) {
        self.stringValue = stringValue
        self.intValue = intValue
    }

    fileprivate init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }

    fileprivate static let `super` = JSONKey(stringValue: "super")!
}

extension DecodingError.Context: Equatable {
    public static func == (lhs: DecodingError.Context, rhs: DecodingError.Context) -> Bool {
        let pathsEqual = lhs.codingPath.count == rhs.codingPath.count && zip(lhs.codingPath, rhs.codingPath).allSatisfy { (a, b) in
            keysEqual(a, b)
        }
        return pathsEqual && lhs.debugDescription == rhs.debugDescription
    }
}

class ZippyJSONTests: XCTestCase {
    let decoder = ZippyJSONDecoder()
    lazy var base64Data = {
        return dataFromFile("base64.json")
    }()
    lazy var twitterData = {
        dataFromFile("twitter.json")
    }()
    lazy var canadaData = {
        self.dataFromFile("canada.json")
    }()

    func dataFromFile(_ file: String) -> Data {
        let path = Bundle(for: type(of: self)).path(forResource: file, ofType: "")!
        let string = try! String(contentsOfFile: path)
        return string.data(using: .utf8)!
    }

    func assertEqualsApple<T: Codable & Equatable>(data: Data, type: T.Type) {
        let testDecoder = ZippyJSONDecoder()
        let appleDecoder = JSONDecoder()
        let testObject = try! testDecoder.decode(type, from: data)
        let appleObject = try! appleDecoder.decode(type, from: data)
        XCTAssertEqual(appleObject, testObject)
    }

    func testRecursiveDecoding() {
        decoder.keyDecodingStrategy = .custom({ (keys) -> CodingKey in
            let recursiveDecoder = ZippyJSONDecoder()
            let data: Data = keys.last!.stringValue.data(using: .utf8)!
            return TestCodingKey(stringValue: try! recursiveDecoder.decode(String.self, from: data))!
        })
    }

  func testLesserUsedFunctions() {
    struct NestedArrayMember: Codable, Equatable {
      let a: Int
    }
    struct Test: Codable, Equatable {
      let nestedArray: [NestedArrayMember]
      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: JSONKey.self)
        var unkeyedContainer = try container.nestedUnkeyedContainer(forKey: JSONKey(stringValue: "array")!)
        let nestedArrayMember = try unkeyedContainer.decode(NestedArrayMember.self)
        nestedArray = [nestedArrayMember]
      }
    }

    testRoundTrip(of: Test.self, json: #"{"array": [{"a": 3}]}"#)
  }

    func _testFailure<T>(of value: T.Type,
                           json: String,
                           outputFormatting: JSONEncoder.OutputFormatting = [],
                           expectedError: DecodingError,
                           dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .deferredToDate,
                           dateDecodingStrategy: ZippyJSONDecoder.DateDecodingStrategy = .deferredToDate,
                           dataEncodingStrategy: JSONEncoder.DataEncodingStrategy = .base64,
                           dataDecodingStrategy: ZippyJSONDecoder.DataDecodingStrategy = .base64,
                           keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys,
                           keyDecodingStrategy: ZippyJSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
                           nonConformingFloatEncodingStrategy: JSONEncoder.NonConformingFloatEncodingStrategy = .throw,
                           nonConformingFloatDecodingStrategy: ZippyJSONDecoder.NonConformingFloatDecodingStrategy = .throw) where T : Decodable, T : Equatable {
        let decoder = ZippyJSONDecoder()
        decoder.dateDecodingStrategy = dateDecodingStrategy
        decoder.dataDecodingStrategy = dataDecodingStrategy
        decoder.nonConformingFloatDecodingStrategy = nonConformingFloatDecodingStrategy
        decoder.keyDecodingStrategy = keyDecodingStrategy
        do {
            let _ = try decoder.decode(T.self, from: json.data(using: .utf8)!)
            XCTFail()
        } catch {
            if let e = error as? DecodingError {
                XCTAssertEqual(e, expectedError)// (e != expectedError) { fatalError() }
            } else {
                XCTFail()
            }
        }
    }

    func testDictionaryStuff() {
        struct Test: Codable, Equatable {
            let a: Bool
        }
        testRoundTrip(of: Test.self, json: #"{"a": true}"#)
        testRoundTrip(of: TopLevelWrapper<Test>.self, json: #"{"value": {"a": true}}"#)
        _testFailure(of: Test.self, json: #"{"b": true}"#, expectedError: DecodingError.keyNotFound(JSONKey(stringValue: "a")!, DecodingError.Context(codingPath: [], debugDescription: "No value associated with a.")))
        _testFailure(of: Test.self, json: #"{}"#, expectedError: DecodingError.keyNotFound(JSONKey(stringValue: "a")!, DecodingError.Context(codingPath: [], debugDescription: "No value associated with a.")))
        _testFailure(of: TopLevelWrapper<Test>.self, json: #"{"value": {}}"#, expectedError: DecodingError.keyNotFound(JSONKey(stringValue: "a")!, DecodingError.Context(codingPath: [], debugDescription: "No value associated with a.")))
        _testFailure(of: TopLevelWrapper<Test>.self, json: #"{"value": {"b": true}}"#, expectedError: DecodingError.keyNotFound(JSONKey(stringValue: "a")!, DecodingError.Context(codingPath: [JSONKey(stringValue: "value")!], debugDescription: "No value associated with a.")))
    }

    func testNestedDecoding() {
        struct Test: Codable, Equatable {
            init(from decoder: Decoder) throws {
                if (try! ZippyJSONDecoder().decode([Int].self, from: "[1]".data(using: .utf8)!) != [1]) {
                    abort()
                }
            }
        }
        testRoundTrip(of: Test.self, json: "{}")
    }

    func testEmptyString() {
        _testFailure(of: [Int].self, json: "", expectedError: DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "The given data was not valid JSON. Error: Empty")))
    }

    func testArrayStuff() {
        struct Test: Codable, Equatable {
            let a: Bool
            let b: Bool

            init(a: Bool, b: Bool) {
                self.a = a
                self.b = b
            }

            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                a = try container.decode(Bool.self)
                b = try container.decode(Bool.self)
            }
        }

        // Goes past the end
        _testFailure(of: Test.self, json: "[true]", expectedError: DecodingError.valueNotFound(Any.self, DecodingError.Context(codingPath: [JSONKey(index: 0)], debugDescription: "Cannot get next value -- unkeyed container is at end.")))
        _testFailure(of: Test.self, json: "[]", expectedError: DecodingError.valueNotFound(Any.self, DecodingError.Context(codingPath: [], debugDescription: "Cannot get next value -- unkeyed container is at end.")))
        _testFailure(of: TopLevelWrapper<Test>.self, json: #"{"value": [true]}"#, expectedError: DecodingError.valueNotFound(Any.self, DecodingError.Context(codingPath: [JSONKey(stringValue: "value")!, JSONKey(index: 0)], debugDescription: "Cannot get next value -- unkeyed container is at end.")))
        _testFailure(of: TopLevelWrapper<Test>.self, json: #"{"value": []}"#, expectedError: DecodingError.valueNotFound(Any.self, DecodingError.Context(codingPath: [JSONKey(stringValue: "value")!], debugDescription: "Cannot get next value -- unkeyed container is at end.")))
        // Left over
        testRoundTrip(of: Test.self, json: "[false, true, false]")
        // Normals
        testRoundTrip(of: Test.self, json: "[false, true]")
        testRoundTrip(of: [[[[Int]]]].self, json: "[[[[]]]]")
        testRoundTrip(of: [[[[Int]]]].self, json: "[[[[2, 3]]]]")
        testRoundTrip(of: [Bool].self, json: "[false, true]")
        _testFailure(of: [Int].self, json: #"{"a": 1}"#, expectedError: DecodingError.typeMismatch([Any].self, DecodingError.Context(codingPath: [], debugDescription: "Tried to unbox array, but it wasn\'t an array")))
    }

    func testInvalidJSON() {
        _testFailure(of: [Int].self, json: "{a: 255}", expectedError: DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "The given data was not valid JSON. Error: Something went wrong while writing to the tape")))
    }
    
    func testRawValuePassedAsJson() {
        // DecodingError.Context(codingPath: <#T##[CodingKey]#>, debugDescription: <#T##String#>, underlyingError: <#T##Error?#>)
        // testRoundTrip(of: [UInt8].self, json: "255")
        // _testFailure(of: UInt8.self, json: "255", expectedError: DecodingError.dataCorrupted(DecodingError.Context(codingPath: [JSONKey(index: 0)], debugDescription: "Parsed JSON number 256 does not fit.")))
        _testFailure(of: Bool.self, json: "false", expectedError: DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "The given data was not valid JSON. Error: Problem while parsing an atom starting with the letter \'f\'")))
        _testFailure(of: Int64.self, json: "255", expectedError: DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "The given data was not valid JSON.")))
    }

    func testInts() {
        testRoundTrip(of: [UInt8].self, json: "[255]")
        _testFailure(of: [UInt8].self, json: "[256]", expectedError: DecodingError.dataCorrupted(DecodingError.Context(codingPath: [JSONKey(index: 0)], debugDescription: "Parsed JSON number 256 does not fit.")))
        _testFailure(of: [UInt8].self, json: "[-1]", expectedError: DecodingError.dataCorrupted(DecodingError.Context(codingPath: [JSONKey(index: 0)], debugDescription: "Parsed JSON number -1 does not fit.")))
        testRoundTrip(of: [Int64].self, json: "[\(Int64.max)]")
        testRoundTrip(of: [Int64].self, json: "[\(Int64.min)]")
        testRoundTrip(of: [UInt64].self, json: "[\(UInt64.max)]")
    }

    func testDifferentTypes() {
        struct Test: Codable, Equatable {
            let i8: Int8
            let i16: Int16
            let i32: Int32
            let i64: Int64
            let u8: UInt8
            let u16: UInt16
            let u32: UInt32
            let u64: UInt64
            let u: UInt64
            let i: Int
        }
        let expected = Test(i8: 1, i16: 2, i32: 3, i64: 4, u8: 5, u16: 6, u32: 7, u64: 8, u: 9, i: 10)
        testRoundTrip(of: Test.self, json: #"{"u8": 1, "u16": 2, "u32": 3, "u64": 4, "i8": 5, "i16": 6, "i32": 7, "i64": 8, "u": 9, "i": 10}"#)
    }

    func testAllKeys() {
        struct Test: Codable {
            let keys: [String]
            init(from decoder: Decoder) throws {
                let container = try! decoder.container(keyedBy: JSONKey.self)
                keys = container.allKeys.map { $0.stringValue }
            }
        }
        let test = try! ZippyJSONDecoder().decode(Test.self, from: #"{"a": 1, "b": 2}"#.data(using: .utf8)!)
        XCTAssertEqual(test.keys, ["a", "b"])
    }

    func testDoubleParsing() {
        testRoundTrip(of: [Double].self, json: "[0.0]")
        testRoundTrip(of: [Double].self, json: "[0.0000]")
        testRoundTrip(of: [Double].self, json: "[-0.0]")
        testRoundTrip(of: [Double].self, json: "[1.0]")
        testRoundTrip(of: [Double].self, json: "[1.11111]")
        testRoundTrip(of: [Double].self, json: "[1.11211e-2]")
        testRoundTrip(of: [Double].self, json: "[1.11211e200]")
    }

    // Run with tsan
    func testConcurrentUsage() {
        let d = ZippyJSONDecoder()
        let testResult = try! d.decode(Twitter.self, from: twitterData)
        var value: Int32 = 0
        for _ in 0..<100 {
            DispatchQueue.global(qos: .userInteractive).async {
                assert(testResult == (try! d.decode(Twitter.self, from: self.twitterData)))
                OSAtomicIncrement32(&value)
            }
        }
        while value < 100 {
            usleep(UInt32(1e5))
        }
    }

    func testCodingKeys() {
        struct Test: Codable, Equatable {
            let a: Int
            let c: Int

            enum CodingKeys: String, CodingKey {
                case a = "b"
                case c
            }
        }

        testRoundTrip(of: Test.self, json: #"{"b": 1, "c": 2}"#)
    }

    func testNull() {
        struct Test: Codable, Equatable {
            let a: Int?
        }
        testRoundTrip(of: Test.self, json: #"{"a": null}"#)
    }

    func run<T: Codable & Equatable>(_ filename: String, _ type: T.Type, keyDecoding: ZippyJSONDecoder.KeyDecodingStrategy = .useDefaultKeys, dateDecodingStrategy: ZippyJSONDecoder.DateDecodingStrategy = .deferredToDate) {
        let json = dataFromFile(filename + ".json")
        testRoundTrip(of: type, json: String(data: json, encoding: .utf8)!,
                      dateDecodingStrategy: dateDecodingStrategy, testPerformance: false)
    }

    func testArrayTypes() {
        struct Test: Codable, Equatable {
            init(from decoder: Decoder) throws {
                var c = try! decoder.unkeyedContainer()
                a = try! c.decode(Int8.self)
                b = try! c.decode(Int16.self)
                cc = try! c.decode(Int32.self)
                d = try! c.decode(Int64.self)
                e = try! c.decode(Int.self)
                f = try! c.decode(UInt8.self)
                g = try! c.decode(UInt16.self)
                h = try! c.decode(UInt32.self)
                i = try! c.decode(UInt64.self)
                j = try! c.decode(UInt.self)
                k = try! c.decode(Float.self)
                l = try! c.decode(Double.self)
            }
            let a: Int8
            let b: Int16
            let cc: Int32
            let d: Int64
            let e: Int
            let f: UInt8
            let g: UInt16
            let h: UInt32
            let i: UInt64
            let j: UInt
            let k: Float
            let l: Double
        }
        testRoundTrip(of: Test.self, json: "[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]")
    }

    func testRealJsons() {
        run("apache_builds", ApacheBuilds.self)
        run("random", random.self)
        run("mesh", mesh.self)
        run("canada", canada.self)
        run("github_events", ghEvents.self, dateDecodingStrategy: .iso8601)
        run("twitter", Twitter.self, keyDecoding: .convertFromSnakeCase)
        run("twitterescaped", Twitter.self)
    }
}
