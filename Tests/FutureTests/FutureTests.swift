//
//  FutureTests.swift
//  FutureTests
//
//  Created by Daniel Leping on 3/12/16.
//  Copyright © 2016 Crossroad Labs, LTD. All rights reserved.
//

import XCTest

import Result
import Boilerplate
import ExecutionContext
import Foundation

#if os(Linux)
    import Glibc
    import RunLoop
#endif

/*@testable*/ import Future

enum TestError : Error {
    case Recoverable
    case Fatal
}

func fibonacci(_ n: Int) -> Int {
    switch n {
    case 0...1:
        return n
    default:
        return fibonacci(n - 1) + fibonacci(n - 2)
    }
}

func getMutablePointer(object: AnyObject) -> UnsafeMutableRawPointer? {
    var obj = object
    var p:UnsafeMutableRawPointer? = nil
    withUnsafeMutablePointer(to: &obj) {
        p = UnsafeMutableRawPointer($0)
    }
    return p
}

/**
 * This extension contains utility methods used in the tests above
 */
extension XCTestCase {
    struct Rand {
        init() {
            #if os(Linux)
             srand(UInt32(time(nil)))
            #endif
        }
        func random(_ count: UInt32) -> UInt32 {
            #if os(Linux)
                return UInt32(rand()) % count
            #else
                return arc4random_uniform(count)
            #endif
        }
    }
    static let random = Rand()
    
    func expectation() -> XCTestExpectation {
        return self.expectation(description: "no description")
    }
    
    func failingFuture<U>() -> Future<U> {
        return future {
            usleep(XCTestCase.random.random(100))
            throw TestError.Recoverable
        }
    }
    
    func succeedingFuture<U>(val: U) -> Future<U> {
        return future {
            usleep(XCTestCase.random.random(100))
            return val
        }
    }
}


class FutureTests: XCTestCase {
    let mQueue = DefaultExecutionContext(kind: .serial)
    
    func testCompletedFuture() {
        let completeExpectation = self.expectation(description:"immediate complete")
        let successExpectation = self.expectation(description: "immediate success")
        
        mQueue.sync {
            let f = Future<Int>(value: 2)
        
            f.onComplete { result in
                XCTAssert(result.value != nil)
                completeExpectation.fulfill()
            }
        
            f.onSuccess { value in
                XCTAssert(value == 2, "Computation should be returned")
                successExpectation.fulfill()
            }
        
            f.onFailure { _ in
                XCTFail("failure block should not get called")
            }
        }
        
        self.waitForExpectations(timeout:2, handler: nil)
    }
    
    func testCompletedVoidFuture() {
        let f = Future<Void>(value: ())
        XCTAssert(f.isCompleted, "void future should be completed")
    }
    
    func testFailedFuture() {
        let completeExpectation = self.expectation(description: "immediate complete")
        let failureExpectation = self.expectation(description: "immediate failure")
        
        mQueue.sync {
            let error = TestError.Recoverable
            let f = Future<Void>(error: error)
            
            f.onComplete { (result:Result<Void, TestError>) in
                switch result {
                case .success(_):
                    XCTAssert(false)
                case .failure(let err):
                    print("Error: \(err)")
                    XCTAssertEqual(err, error)
                }
                completeExpectation.fulfill()
            }
            
            f.onFailure { (err:TestError) in
                print("Error 2: \(err)")
                XCTAssert(err == error)
                failureExpectation.fulfill()
            }
            
            f.onSuccess { value in
                XCTFail("success should not be called")
            }
        }
        
        self.waitForExpectations(timeout:2, handler: nil)
    }
    
    // Swift on linux has crashes with NSError
    #if !os(Linux)
    func testNSError() {
        let completeExpectation = self.expectation(description: "immediate complete")
        let failureExpectation = self.expectation(description: "immediate failure")
        
        mQueue.sync {
            let error = NSError(domain: "test", code: 101, userInfo: nil)
            let f = Future<Void>(error:error)
            f.onComplete { (result:Result<Void, NSError>) in
                switch result {
                case .success(_):
                    XCTAssert(false)
                case .failure(let err):
                    print("Error: \(err)")
                    XCTAssertEqual(err, error)
                }
                completeExpectation.fulfill()
            }
            
            f.onFailure { (err:NSError) in
                print("Error 2: \(err)")
                XCTAssert(err.isEqual(error))
                failureExpectation.fulfill()
            }
            
            f.onSuccess { value in
                XCTFail("success should not be called")
            }
        }
        self.waitForExpectations(timeout:2, handler: nil)
    }
    
    func testNSErrorThrow() {
        let completeExpectation = self.expectation(description: "immediate complete")
        let failureExpectation = self.expectation(description: "immediate failure")
        
        mQueue.sync {
            let error = NSError(domain: "test", code: 101, userInfo: nil)
            let f = future {
                throw error
            }
            f.onComplete { (result:Result<Void, NSError>) in
                switch result {
                case .success(_):
                    XCTAssert(false)
                case .failure(let err):
                    print("Error: \(err)")
                    XCTAssertEqual(err, error)
                }
                completeExpectation.fulfill()
            }
            
            f.onFailure { (err:NSError) in
                print("Error 2: \(err)")
                XCTAssert(err.isEqual(error))
                failureExpectation.fulfill()
            }
            
            f.onSuccess { value in
                XCTFail("success should not be called")
            }
        }
        self.waitForExpectations(timeout:2, handler: nil)
    }
    #endif
    
    func testFutureBasic() {
        let exp = self.expectation(description: "6")
        
        mQueue.sync {
            let f = future {
                return "716"
            }
            
            f.onComplete { (result:Result<String, NoError>) in
                print("1:", result.value!)
            }
            
            f.onComplete { result in
                print("2:", result.value!)
            }
            
            let f2:Future<String> = future {
                throw TestError.Recoverable
            }
            
            f2.onComplete { (result:Result<String, NoError>) in
                print("SHOULD NOT PRINT")
            }
            
            f2.onComplete { result in
                print("Any:", result.error!.error)
            }
            
            f2.onComplete { (result:Result<String, TestError>) in
                print("Typed:", result.error!)
            }
            
            f2.onFailure { (e:TestError) in
                print("EEEE!!!!EEEE:", e)
            }
            
            f.flatMap { value in
                Int(value)
            }.onSuccess { value in
                print("!@#$%^&OUR INT:", value)
            }
            
            let f3 = f2.recover { e in
                return "recovered"
            }
            
            let f4 = f2.recover { (e:TestError) in
                return "678"
            }
            
            let f5 = f2.recoverWith { e in
                return future {
                    return "819"
                }
            }
            
            let f6 = f2.recoverWith { e in
                return Future(value: "347")
            }
            
            f3.flatMap { str in
                return Int(str)
            }.onFailure { (e:Error) in
                print("recovered 3:", e)
            }
            
            f4.flatMap { str in
                return Int(str)
            }.onSuccess { value in
                print("recovered 4:", value)
            }
            
            f5.flatMap { str in
                return Int(str)
            }.onSuccess { value in
                print("recovered 5:", value)
            }
            
            
            
            f6.flatMap { str in
                return Int(str)
            }.onSuccess { value in
                print("recovered 6:", value)
                exp.fulfill()
            }
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
        
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    func testControlFlowSyntax() {
        
        let e = self.expectation(description: "the computation succeeds")
        
        mQueue.sync {
            let f = future {fibonacci(10)}
        
            f.onSuccess { value in
                XCTAssert(value == 55)
                e.fulfill()
            }
        }
        
        self.waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testControlFlowSyntaxWithError() {
        
        let failureExpectation = self.expectation(description: "failure expected")
        
        mQueue.sync {
        
            let f : Future<String?> = future {
                throw TestError.Recoverable
            }
        
            f.onFailure { error in
                XCTAssert(error as? TestError == .Recoverable)
                failureExpectation.fulfill()
            }
        }
        
        self.waitForExpectations(timeout:3, handler: nil)
    }
    
//    func testAutoClosure() {
//        let names = ["Steve", "Tim"]
//        
//        let f = future(names.count)
//        let e = self.expectation()
//        
//        f.onSuccess { value in
//            XCTAssert(value == 2)
//            e.fulfill()
//        }
//        
//        self.waitForExpectations(withTimeout: 2, handler: nil)
//        
//        let e1 = self.expectation()
//        Future<Int>(value: fibonacci(10)).onSuccess { value in
//            XCTAssert(value == 55);
//            e1.fulfill()
//        }
//        
//        self.waitForExpectationsWithTimeout(2, handler: nil)
//    }

//    func testAutoClosureWithResult() {
//        let f = future(Result<Int, NoError>(value:2))
//        let e = self.expectation()
//        
//        f.onSuccess { value in
//            XCTAssert(value == 2)
//            e.fulfill()
//        }
//        
//        self.waitForExpectations(withTimeout: 2, handler: nil)
//        
//        let f1 = future(Result<Int, TestError>(error: .Recoverable))
//        let e1 = self.expectation()
//        
//        f1.onFailure { (error: TestError) in
//            XCTAssert(error == TestError.Recoverable)
//            e1.fulfill()
//        }
//        
//        self.waitForExpectations(withTimeout: 2, handler: nil)
//    }
    
    
    func testCustomExecutionContext() {
        let e = self.expectation(description: "immediate success expectation")
        
        let f = future(context: immediate) {
            fibonacci(10)
        }
        
        f.onSuccess { value in
            e.fulfill()
        }
        
        #if os(Linux)
            (RunLoop.current as? RunnableRunLoopType)?.run(2)
        #endif
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testMainExecutionContext() {
        let e = self.expectation()
        
        future { _ -> Int in
            XCTAssert(!Thread.isMain)
            return 1
        }.settle(in: main).onSuccess { value in
            XCTAssert(Thread.isMain)
            e.fulfill()
        }
        
        #if os(Linux)
            (RunLoop.current as? RunnableRunLoopType)?.run(2)
        #endif
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testDefaultCallbackExecutionContextFromMain() {
        let f = Future<Int>(value: 1)
        let e = self.expectation()
        f.onSuccess { _ in
            XCTAssert(Thread.isMain, "the callback should run on main")
            e.fulfill()
        }
        
        #if os(Linux)
            (RunLoop.current as? RunnableRunLoopType)?.run(2)
        #endif
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testDefaultCallbackExecutionContextFromBackground() {
        let f = Future<Int>(value: 1)
        let e = self.expectation()
        global.execute {
            f.settle(in: ExecutionContext.current).onSuccess { _ in
                XCTAssert(!Thread.isMain, "the callback should not be on the main thread")
                e.fulfill()
            }
        }
        
        #if os(Linux)
            (RunLoop.current as? RunnableRunLoopType)?.run(2)
        #endif
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }

    func testFilteredOutError() {
        let f: Future<Int> = future{3}.filter { _ in false }
        
        let e = self.expectation()
        f.onFailure { (err:FutureError) in
            XCTAssertEqual(err, FutureError.FilteredOut)
            e.fulfill()
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }

    // MARK: Functional Composition
    
//    func testAndThen() {
//        
//        var answer = 10
//        
//        let e = self.expectation()
//        
//        let f = Future<Int>(value: 4)
//        let f1 = f.andThen { result in
//            if let val = result.value {
//                answer *= val
//            }
//        }
//        
//        let f2 = f1.andThen { result in
//            answer += 2
//        }
//        
//        f1.onSuccess { fval in
//            f1.onSuccess { f1val in
//                f2.onSuccess { f2val in
//                    
//                    XCTAssertEqual(fval, f1val, "future value should be passed transparently")
//                    XCTAssertEqual(f1val, f2val, "future value should be passed transparantly")
//                    
//                    e.fulfill()
//                }
//            }
//        }
//        
//        self.waitForExpectations(withTimeout: 20, handler: nil)
//        
//        XCTAssertEqual(42, answer, "andThens should be executed in order")
//    }
    
    func testSimpleMap() {
        let e = self.expectation()
        
        func divideByFive(i: Int) -> Int {
            return i / 5
        }
        
        mQueue.sync {
            Future<Int>(value: fibonacci(10)).map(divideByFive).onSuccess { val in
                XCTAssertEqual(val, 11, "The 10th fibonacci number (55) divided by 5 is 11")
                e.fulfill()
                return
            }
            return
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }

    func testMapSuccess() {
        let e = self.expectation()
        
        mQueue.sync {
            // Had to split here to lets. It feels like swift compiler has a bug and can not do this chain in full
            // Hopefully they will resolve the issue in the next versions and soon enough
            // No details (like particular types) were added on top though
            // Actually it still is quite a rare case when you map a just created future
            future {
                fibonacci(10)
            }.map { value -> String in
                if value > 5 {
                    return "large"
                }
                return "small"
            }.map { sizeString -> Bool in
                return sizeString == "large"
            }.onSuccess { numberIsLarge in
                XCTAssert(numberIsLarge)
                e.fulfill()
            }
            return
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testMapFailure() {
        
        let e = self.expectation()
        
        mQueue.sync {
            future { () -> Result <Int, TestError> in
                Result(error: TestError.Recoverable)
            }.map { number in
                XCTAssert(false, "map should not be evaluated because of failure above")
            }.map { number in
                XCTAssert(false, "this map should also not be evaluated because of failure above")
            }.onFailure { (error:TestError) -> Void in
                XCTAssertEqual(error, TestError.Recoverable)
                e.fulfill()
            }
            return
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testRecover() {
        let e = self.expectation()
//      let e1 = self.expectation()
        
        mQueue.sync {
            Future<Int>(error: TestError.Recoverable).recover { _ in
                return 3
            }.onSuccess { val in
                XCTAssertEqual(val, 3)
                e.fulfill()
            }
        
//          let recov: () -> Int = {
//              return 5
//          }
//        

//          (Future<Int>(error: TestError.Recoverable) ?? recov()).onSuccess { value in
//              XCTAssert(value == 5)
//              e1.fulfill()
//          }
            return
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testSkippedRecover() {
        let e = self.expectation()
        
        mQueue.sync {
            future {
                3
            }.recover { _ in
                XCTFail("recover task should not be executed")
                return 5
            }.onSuccess { value in
                XCTAssert(value == 3)
                e.fulfill()
            }
        
//          let e1 = self.expectation()
//        
//        
//          let recov: () -> Int = {
//              XCTFail("recover task should not be executed")
//              return 5
//          }
//        
//          (future(3) ?? recov()).onSuccess { value in
//              XCTAssert(value == 3)
//              e1.fulfill()
//          }
            return
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testRecoverWith() {
        let e = self.expectation()
        
        mQueue.sync {
            future {
                Result(error: TestError.Recoverable)
            }.recoverWith { _ in
                return future { _ in
                    fibonacci(5)
                }
            }.onSuccess { value in
                XCTAssert(value == 5)
                e.fulfill()
            }
        
//          let e1 = self.expectation()
//        
//          let f: Future<Int, NoError> = Future<Int, TestError>(error: TestError.Recoverable) ?? future(fibonacci(5))
//        
//          f.onSuccess {
//              XCTAssertEqual($0, 5)
//              e1.fulfill()
//          }
            return
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testRecoverThrowError() {
        let e = self.expectation()
        
        mQueue.sync {
            Future<Int>(error: TestError.Recoverable).recover { (error: TestError) in
                throw TestError.Fatal
            }.onFailure { (error:TestError) in
                XCTAssertEqual(error, TestError.Fatal)
                e.fulfill()
            }
            return
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testZip() {
        let f = Future<Int>(value: 1)
        let f1 = Future<Int>(value: 2)
        
        let e = self.expectation()
        
        f.zip(f1).onSuccess { (a, b) in
            XCTAssertEqual(a, 1)
            XCTAssertEqual(b, 2)
            e.fulfill()
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testZipThisFails() {
        let f: Future<Bool> = future { () -> Result<Bool,TestError> in
            Thread.sleep(timeout: 1)
            return Result(error: TestError.Recoverable)
        }
        
        let f1 = Future<Int>(value: 2)
        
        let e = self.expectation()
        
        f.zip(f1).onFailure { (error:TestError) in
            XCTAssertEqual(error, TestError.Recoverable)
            e.fulfill()
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testZipThatFails() {
        let f = future { () -> Result<Int,TestError> in
            Thread.sleep(timeout: 1)
            return Result(error: TestError.Recoverable)
        }
        
        let f1 = Future<Int>(value: 2)
        
        let e = self.expectation()
        
        f1.zip(f).onFailure { (error:TestError) in
            XCTAssertEqual(error, TestError.Recoverable)
            e.fulfill()
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testZipBothFail() {
        let f = future { () -> Result<Int,TestError> in
            Thread.sleep(timeout: 1)
            return Result(error: TestError.Recoverable)
        }
        
        let f1 = future { () -> Result<Int,TestError> in
            Thread.sleep(timeout: 1)
            return Result(error: TestError.Fatal)
        }
        
        let e = self.expectation()
        
        f.zip(f1).onFailure { (error:TestError) in
            XCTAssertEqual(error, TestError.Recoverable)
            e.fulfill()
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testFilterNoSuchElement() {
        let e = self.expectation()
        
        Future<Int>(value: 3).filter { $0 > 5}.onComplete { (result:Result<Int, FutureError>) in
            XCTAssertEqual(result.error!, FutureError.FilteredOut, "filter should yield no result")
            e.fulfill()
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testFilterPasses() {
        let e = self.expectation()
        Future<String>(value: "Daniel").filter { $0.hasPrefix("Da") }.onComplete { result in
            XCTAssertEqual(result.value!, "Daniel", "Filter should pass")
            
            e.fulfill()
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testFilterNotPasses() {
        let e = self.expectation()
        Future<String>(value: "Daniel").filterNot { $0.hasPrefix("Cr") }.onComplete { result in
            XCTAssertEqual(result.value!, "Daniel", "Filter should pass")
            
            e.fulfill()
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testFilterFailedFuture() {
        let f = Future<Int>(error: TestError.Recoverable)
        
        let e = self.expectation()
        f.filter { _ in false }.onFailure { (error:TestError) in
            XCTAssert(error == TestError.Recoverable)
            e.fulfill()
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
//    func testReadyFuture() {
//        var x = 10
//        let f: Future<Void> = future { () -> Void in
//            Thread.sleep(0.5)
//            x = 3
//        }
//        f.ready()
//        XCTAssertEqual(x, 3)
//    }
//    
//    func testReadyFutureWithTimeout() {
//        let f: Future<Void> = future {
//            Thread.sleep(0.5)
//        }
//        
//        XCTAssert(f.ready(0.1) == nil)
//        
//        XCTAssert(f.ready(0.5) != nil)
//    }
    
//    func testReadyCompletedFuture() {
//        let f = Future<Int>(value: 1)
//        XCTAssertEqual(f.ready().value!, 1)
//    }

    func testFlatMap() {
        let e = self.expectation()
        
        let finalString = "Greg"
        
        mQueue.sync {
            let flatMapped = Future<String>(value: "Thomas").flatMap { _ in
                return Future<String>(value: finalString)
            }
        
            flatMapped.onSuccess { s in
                XCTAssertEqual(s, finalString, "strings are not equal")
                e.fulfill()
            }
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testFlatMapByPassingFunction() {
        let e = self.expectation()
        
        func toString(n: Int) -> Future<String> {
            return Future<String>(value: "\(n)")
        }
        
        let n = 1
        let flatMapped = Future<Int>(value: n).flatMap(toString)
        
        flatMapped.onSuccess { s in
            XCTAssertEqual(s, "\(n)", "strings are not equal")
            e.fulfill()
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    func testFlatMapResult() {
        let e = self.expectation()
        
        mQueue.sync {
            Future<Int>(value: 3).flatMap { _ in
                Result<Int, AnyError>(value: 22)
            }.onSuccess { val in
                XCTAssertEqual(val, 22)
                e.fulfill()
            }
            return
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    
    // MARK: Advanced Tests

    // Creates a lot of futures and adds completion blocks concurrently, which should all fire
    func testStress() {
            let instances = 100;
            var successfulFutures = [Future<Int>]()
            var failingFutures = [Future<Int>]()
            let contexts: [ExecutionContextProtocol] = [immediate, main, global]
            
            let randomContext: () -> ExecutionContextProtocol = { contexts[Int(arc4random_uniform(UInt32(contexts.count)))] }
            let randomFuture: () -> Future<Int> = {
                if arc4random() % 2 == 0 {
                    return successfulFutures[Int(arc4random_uniform(UInt32(successfulFutures.count)))]
                } else {
                    return failingFutures[Int(arc4random_uniform(UInt32(failingFutures.count)))]
                }
            }
            
            var finalSum = 0;
            
            for _ in 1...instances {
                var future: Future<Int>
                if arc4random() % 2 == 0 {
                    let futureResult: Int = Int(arc4random_uniform(10))
                    finalSum += futureResult
                    future = self.succeedingFuture(val: futureResult)
                    successfulFutures.append(future)
                } else {
                    future = self.failingFuture()
                    failingFutures.append(future)
                }
                
                let context = randomContext()
                let e = self.expectation(description: "future completes in context \(context)")
                
                future.settle(in: context).onComplete { (res:Result<Int, AnyError>) in
                    e.fulfill()
                }
                
                
            }
            
            for _ in 1...instances*10 {
                let f = randomFuture()
                
                let context = randomContext()
                let e = self.expectation(description: "future completes in context \(context)")
                
                global.execute {
                    usleep(arc4random_uniform(100))
                    
                    f.settle(in: context).onComplete { (res:Result<Int, AnyError>) in
                        e.fulfill()
                    }
                }
            }
            
            self.waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testSerialCallbacks() {
        let p = Promise<Void>()
        
        var executingCallbacksGlobal = 0
        let globalFuture = p.future.settle(in: global)
        var executingCallbacksMain = 0
        let mainFuture = p.future.settle(in: main)
        
        
        for _ in 0..<10 {
            let e = self.expectation()
            globalFuture.onComplete { _ in
                XCTAssert(executingCallbacksGlobal == 0, "This should be the only executing callback")
                
                executingCallbacksGlobal += 1
                
                // sleep a bit to increase the chances of other callback blocks executing
                Thread.sleep(timeout: 0.06)
                
                executingCallbacksGlobal -= 1
                
                e.fulfill()
            }
            
            let e1 = self.expectation()
            mainFuture.onComplete { _ in
                XCTAssert(executingCallbacksMain == 0, "This should be the only executing callback")
                
                executingCallbacksMain += 1
                
                // sleep a bit to increase the chances of other callback blocks executing
                Thread.sleep(timeout: 0.06)
                
                executingCallbacksMain -= 1
                
                e1.fulfill()
            }
        }
        
        XCTAssert(p.trySuccess(value: ()))
        
        #if os(Linux)
            (RunLoop.current as? RunnableRunLoopType)?.run(5)
        #endif
        
        self.waitForExpectations(timeout: 5, handler: nil)
    }
    
    #if !os(Linux) || dispatch
    // Test for https://github.com/Thomvis/BrightFutures/issues/18
    func testCompletionBlockOnMainQueue() {
        let key = DispatchSpecificKey<String>()
        let value = "value"
        
        DispatchQueue.main.setSpecific(key: key, value: value)
        
        XCTAssertEqual(DispatchQueue.main.getSpecific(key: key), value, "value should have been set on the main (i.e. current) queue")
        
        let e = self.expectation()
        Future<Int>(value: 1).settle(in: main).onSuccess { val in
            XCTAssertEqual(DispatchQueue.getSpecific(key: key), value, "we should now too be on the main queue")
            e.fulfill()
        }
        
        self.waitForExpectations(timeout: 2, handler: nil)
    }
    #endif
    
    class DeinitMockObject {
        let _expectation:XCTestExpectation
        
        init(_ expectation:XCTestExpectation) {
            self._expectation = expectation
        }
        
        deinit {
            _expectation.fulfill()
        }
    }
    
    func testFutureFunReleasesObject() {
        let finish = self.expectation(description: "finish")
        
        repeat {
            let expectation = self.expectation(description: "deinit")
            let f = future {
                DeinitMockObject(expectation)
            }
            f.onSuccess { _ in
                finish.fulfill()
            }
        } while false
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testPromiseInContextReleasesObject() {
        let finish = self.expectation(description: "finish")
        
        repeat {
            let expectation = self.expectation(description: "deinit")
            let p = Promise<DeinitMockObject>()
            p.future.onSuccess { _ in
                finish.fulfill()
            }
            global.execute {
                XCTAssert(p.trySuccess(value: DeinitMockObject(expectation)))
            }
        } while false
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testPromiseReleasesObject() {
        let finish = self.expectation(description: "finish")
        
        repeat {
            let expectation = self.expectation(description: "deinit")
            let p = Promise<DeinitMockObject>()
            p.future.onSuccess { _ in
                finish.fulfill()
            }
            XCTAssert(p.trySuccess(value: DeinitMockObject(expectation)))
        } while false
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testFutureReleasesObject() {
        let finish = self.expectation(description: "finish")
        
        repeat {
            let expectation = self.expectation(description: "deinit")
            let f = Future<DeinitMockObject>(value: DeinitMockObject(expectation))
            f.onSuccess { _ in
                finish.fulfill()
            }
        } while false
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testInvalidationToken() {
        let token = InvalidationToken()

        let exp1 = self.expectation(description: "exp1")
        let exp2 = self.expectation(description: "exp2")
        let exp3 = self.expectation(description: "exp3")
        
        Future<Void>(value: ()).onSuccess(token: token) {
            token.valid = false
            exp1.fulfill()
        }.onSuccess(token: token) {
            XCTFail("should not get called")
        }.onSuccess {
            exp2.fulfill()
            token.valid = true
        }.onSuccess(token: token) {
            exp3.fulfill()
        }
        
        self.waitForExpectations(timeout: 1)
    }
    
    func testRelease() {
        weak var f: Future<Int>? = nil
        
        let expectationSuccess = self.expectation(description: "Success")
        let expectationComplete = self.expectation(description: "Complete")
        
        var f1: Future<Int>? = Future<Int>(value: 1).map { $0 }.recover { _ in
            return 0
        }.onSuccess { _ in
            expectationSuccess.fulfill()
        }.onComplete { _ in
            expectationComplete.fulfill()
        }
        
        f = f1
        XCTAssertNotNil(f1);
        XCTAssertNotNil(f);
        f1 = nil
        
        self.waitForExpectations(timeout: 1, handler: nil)
        
        XCTAssertNil(f1)
        XCTAssertNil(f)
    }

}

#if os(Linux)
extension FutureTests {
	static var allTests : [(String, (FutureTests) -> () throws -> Void)] {
		return [
			("testCompletedFuture", testCompletedFuture),
			("testCompletedVoidFuture", testCompletedVoidFuture),
			("testFailedFuture", testFailedFuture),
			("testFutureBasic", testFutureBasic),
			("testControlFlowSyntax", testControlFlowSyntax),
			("testControlFlowSyntaxWithError", testControlFlowSyntaxWithError),
			("testAutoClosure", testAutoClosure),
			("testAutoClosureWithResult", testAutoClosureWithResult),
			("testCustomExecutionContext", testCustomExecutionContext),
			("testMainExecutionContext", testMainExecutionContext),
			("testDefaultCallbackExecutionContextFromMain", testDefaultCallbackExecutionContextFromMain),
			("testDefaultCallbackExecutionContextFromBackground", testDefaultCallbackExecutionContextFromBackground),
			("testFilteredOutError", testFilteredOutError),
			("testAndThen", testAndThen),
			("testSimpleMap", testSimpleMap),
			("testMapSuccess", testMapSuccess),
			("testMapFailure", testMapFailure),
			("testRecover", testRecover),
			("testSkippedRecover", testSkippedRecover),
			("testRecoverWith", testRecoverWith),
			("testRecoverThrowError", testRecoverThrowError),
			("testZip", testZip),
			("testZipThisFails", testZipThisFails),
			("testZipThatFails", testZipThatFails),
			("testZipBothFail", testZipBothFail),
			("testFilterNoSuchElement", testFilterNoSuchElement),
			("testFilterPasses", testFilterPasses),
			("testFilterNotPasses", testFilterNotPasses),
			("testFilterFailedFuture", testFilterFailedFuture),
			("testReadyFuture", testReadyFuture),
			("testReadyFutureWithTimeout", testReadyFutureWithTimeout),
			("testReadyCompletedFuture", testReadyCompletedFuture),
			("testFlatMap", testFlatMap),
			("testFlatMapByPassingFunction", testFlatMapByPassingFunction),
			("testFlatMapResult", testFlatMapResult),
			("testStress", testStress),
			("testSerialCallbacks", testSerialCallbacks),
			("testFutureFunReleasesObject", testFutureFunReleasesObject),
			("testPromiseInContextReleasesObject", testPromiseInContextReleasesObject),
			("testPromiseReleasesObject", testPromiseReleasesObject),
			("testFutureReleasesObject", testFutureReleasesObject),
			("testInvalidationToken", testInvalidationToken),
			("testRelease", testRelease),
		]
	}
}
#endif