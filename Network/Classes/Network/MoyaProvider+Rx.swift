//
//  Moya+Extension.swift
//  RHMoyaCache
//
//  Created by 荣恒 on 2018/9/28.
//  Copyright © 2018 荣恒. All rights reserved.
//

import Foundation
import RxSwift
import Moya


extension MoyaProvider: ReactiveCompatible {}

// MARK: - 自己封装
public extension Reactive where Base: MoyaProviderType {
    
    /// 请求数据，包括网络和缓存
    func request(_ token : Base.Target) -> Observable<Response> {
        let network = requestNetwork(token).map { Optional($0) }.startWith(nil)
        let cache = requestCache(token).map { Optional($0) }.startWith(nil)
        
        return Observable.combineLatest(cache,network)
            .flatMap { responses -> Observable<Response> in
                switch responses {
                case (let .some(cacheResponse),nil): return .just(cacheResponse)
                case (_, let .some(networkResponse)): return .just(networkResponse)
                default: return .empty()
                }
        }
    }
    
    func requestNetwork(_ token : Base.Target) -> Observable<Response> {
        /// 先判断是否有网
        guard ReachabilityService.shared.isHasNetwork else { return .error(NetworkError.error(value: "没有网络可用")) }
        
        /// 开始网络请求
        return requestResponse(token)
            .do(onNext: { response in
                /// 成功请求后缓存数据
                if let token = token as? CacheType, token.cache == .cacheResponse {
                    token.cache(response: response)
                }
            }, onError: { error in
                /// 失败后缓存请求
                if let token = token as? CacheType, token.cache == .cacheRequest {
                    token.cacheRequest()
                }
            })
    }
    
    func requestCache(_ token : Base.Target) -> Observable<Response> {
        let disposable = Disposables.create()
        
        return Observable<Response>.create { observer in
            guard let token = token as? CacheType,
                let response = try? token.getResponse() else { return disposable }
            
            observer.onNext(response)
            observer.onCompleted()
            
            return disposable
        }
    }
    
}


// MARK: - Moya/RxSwift
public extension Reactive where Base: MoyaProviderType {
    
    /// 请求网络数据基本方法，不加任何逻辑
    func requestResponse(_ token: Base.Target, callbackQueue: DispatchQueue? = nil) -> Observable<Response> {
        return Observable.create({ [weak base] observer in
            let cancellableToken = base?.request(token, callbackQueue: callbackQueue, progress: nil) { result in
                switch result {
                case let .success(response):
                    observer.onNext(response)
                    observer.onCompleted()
                case let .failure(error):
                    observer.onError(error)
                }
            }
            
            return Disposables.create {
                cancellableToken?.cancel()
            }
        })
    }

    /// Designated request-making method with progress.
    func requestWithProgress(_ token: Base.Target, callbackQueue: DispatchQueue? = nil) -> Observable<ProgressResponse> {
        let progressBlock: (AnyObserver) -> (ProgressResponse) -> Void = { observer in
            return { progress in
                observer.onNext(progress)
            }
        }

        let response: Observable<ProgressResponse> = Observable.create { [weak base] observer in
            let cancellableToken = base?.request(token, callbackQueue: callbackQueue, progress: progressBlock(observer)) { result in
                switch result {
                case .success:
                    observer.onCompleted()
                case let .failure(error):
                    observer.onError(error)
                }
            }

            return Disposables.create {
                cancellableToken?.cancel()
            }
        }

        // Accumulate all progress and combine them when the result comes
        return response.scan(ProgressResponse()) { last, progress in
            let progressObject = progress.progressObject ?? last.progressObject
            let response = progress.response ?? last.response
            return ProgressResponse(progress: progressObject, response: response)
        }
    }
}

