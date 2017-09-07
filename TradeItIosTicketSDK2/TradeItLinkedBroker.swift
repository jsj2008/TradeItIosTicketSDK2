import PromiseKit

@objc public class TradeItLinkedBroker: NSObject {
    public var accountsLastUpdated: Date?
    public var accounts: [TradeItLinkedBrokerAccount] = []
    private var _error: TradeItErrorResult?
    var error: TradeItErrorResult? {
        set(newError) {
            guard newError?.errorCode != .brokerExecutionError,
                newError?.errorCode != .paramsError
            else {
                return
            }

            self._error = newError

            self.isAccountLinkDelayedError = newError?.isAccountLinkDelayedError() ?? false
            if self.isAccountLinkDelayedError {
                // We need to cache the isAccountLinkDelayedError property to be able to show the error when we relaunch the app
                TradeItSDK.linkedBrokerCache.cache(linkedBroker: self)
            }
        }
        get { return self._error }
    }
    public var isAccountLinkDelayedError: Bool = false
    public var userId: String {
        get {
            return linkedLogin.userId
        }
    }
    
    var session: TradeItSession
    var linkedLogin: TradeItLinkedLogin

    public var brokerName: String {
        return self.linkedLogin.broker
    }
    
    internal var balanceService: TradeItBalanceService
    internal var positionService: TradeItPositionService
    internal var tradeService: TradeItTradeService
    internal var fxTradeService: TradeItFxTradeService
    internal var orderService: TradeItOrderService
    
    public var brokerLongName: String {
        return self.linkedLogin.brokerLongName
    }

    public init(session: TradeItSession, linkedLogin: TradeItLinkedLogin) {
        self.session = session
        self.linkedLogin = linkedLogin
        self.balanceService = TradeItBalanceService(session: session)
        self.positionService = TradeItPositionService(session: session)
        self.tradeService = TradeItTradeService(session: session)
        self.fxTradeService = TradeItFxTradeService(session: session)
        self.orderService = TradeItOrderService(session: session)
        super.init()
        
        self.setUnauthenticated()
    }

    public func authenticate(
        onSuccess: @escaping () -> Void,
        onSecurityQuestion: @escaping (
            TradeItSecurityQuestionResult,
            _ submitAnswer: @escaping (String) -> Void,
            _ onCancelSecurityQuestion: @escaping () -> Void
        ) -> Void,
        onFailure: @escaping (TradeItErrorResult) -> Void
    ) -> Void {
        let authenticationResponseHandler = YCombinator { handler in
            { (tradeItResult: TradeItResult) in
                switch tradeItResult {
                case let authenticationResult as TradeItAuthenticationResult:
                    self.clearError()

                    let accounts = authenticationResult.accounts as! [TradeItBrokerAccount]

                    self.updateLinkedBrokerAccounts(fromBrokerAccounts: accounts)

                    TradeItSDK.linkedBrokerCache.cache(linkedBroker: self)

                    onSuccess()
                case let securityQuestion as TradeItSecurityQuestionResult:
                    onSecurityQuestion(
                        securityQuestion,
                        { securityQuestionAnswer in
                            self.session.answerSecurityQuestion(securityQuestionAnswer, withCompletionBlock: handler)
                        },
                        {
                            handler(
                                TradeItErrorResult(
                                    title: "Authentication failed",
                                    message: "The security question was canceled.",
                                    code: .sessionError
                                )
                            )
                        }
                    )
                case let error as TradeItErrorResult:
                    self.error = error
                    onFailure(error)
                default:
                    handler(
                        TradeItErrorResult(
                            title: "Could not authenticate",
                            code: .sessionError
                        )
                    )
                }
            }
        }

        self.session.authenticate(linkedLogin, withCompletionBlock: authenticationResponseHandler)
    }

    public func authenticateIfNeeded(
        onSuccess: @escaping () -> Void,
        onSecurityQuestion: @escaping (
            TradeItSecurityQuestionResult,
            _ submitAnswer: @escaping (String) -> Void,
            _ onCancelSecurityQuestion: @escaping () -> Void
        ) -> Void,
        onFailure: @escaping (TradeItErrorResult) -> Void
    ) -> Void {
        guard let error = self.error else {
                onSuccess()
                return
        }

        if error.requiresAuthentication() {
            self.authenticate(
                onSuccess: onSuccess,
                onSecurityQuestion: onSecurityQuestion,
                onFailure: onFailure
            )
        } else if error.requiresRelink() {
            onFailure(error)
        } else {
            onSuccess()
        }
    }

    public func refreshAccountBalances(
        force: Bool = true,
        cacheResult: Bool = true,
        onFinished: @escaping () -> Void
    ) {
        let promises = accounts.filter { account in
            return force || (account.balance == nil && account.fxBalance == nil)
        }.map { account in
            return Promise<> { fulfill, reject in
                account.getAccountOverview(
                    cacheResult: false, // Cache at the end so we don't cache the entire linked broker multiple times
                    onSuccess: { _ in
                        fulfill()
                    },
                    onFailure: { errorResult in
                        fulfill()
                    }
                )
            }
        }

        _ = when(resolved: promises).always {
            if cacheResult {
                TradeItSDK.linkedBrokerCache.cache(linkedBroker: self)
            }
            onFinished()
        }
    }

    public func getEnabledAccounts() -> [TradeItLinkedBrokerAccount] {
        return self.accounts.filter { return $0.isEnabled }
    }

    public func isStillLinked() -> Bool {
        let linkedBrokers = TradeItSDK.linkedBrokerManager.linkedBrokers
        return linkedBrokers.index(of: self) != nil
    }

    public func findAccount(byAccountNumber accountNumber: String) -> TradeItLinkedBrokerAccount? {
        let matchingAccounts = self.accounts.filter { (account: TradeItLinkedBrokerAccount) -> Bool in
            return account.accountNumber == accountNumber
        }

        return matchingAccounts.first
    }

    public func getFxQuote(
        symbol: String,
        onSuccess: @escaping (TradeItQuote) -> Void,
        onFailure: @escaping (TradeItErrorResult) -> Void
    ) {
        let data = TradeItFxQuoteRequest()
        data.symbol = symbol
        data.token = self.session.token

        let request = TradeItRequestFactory.buildJsonRequest(
            for: data,
            emsAction: "brokermarketdata/getFxRate",
            environment: self.session.connector.environment
        )

        self.session.connector.send(
            request,
            targetClassType: TradeItQuotesResult.self,
            withCompletionBlock: { result in
                if let quotesResult = result as? TradeItQuotesResult,
                    let quote = quotesResult.quotes?.first as? TradeItQuote {
                    onSuccess(quote)
                } else if let errorResult = result as? TradeItErrorResult {
                    onFailure(errorResult)
                } else {
                    onFailure(
                        TradeItErrorResult(
                            title: "Market data failed",
                            message: "Could not fetch quote. Please try again."
                        )
                    )
                }
            }
        )
    }

    // MARK: Internal
    internal func clearError() {
        self.error = nil
    }
    
    internal func setUnauthenticated() {
        self.error = TradeItErrorResult(
            title: "Linked Broker initialized from keychain",
            message: "Linked broker must to be authenticated before using.",
            code: .sessionError
        )
    }
    
    // MARK: Private

    private func updateLinkedBrokerAccounts(fromBrokerAccounts accounts: [TradeItBrokerAccount]) {
        let newLinkedBrokerAccounts = accounts.map { account -> TradeItLinkedBrokerAccount in
            if let existingAccount = findAccount(byAccountNumber: account.accountNumber) {
                existingAccount.accountName = account.name
                existingAccount.accountNumber = account.accountNumber
                existingAccount.accountIndex = account.accountIndex
                existingAccount.accountBaseCurrency = account.accountBaseCurrency
                existingAccount.orderCapabilities = account.orderCapabilities as? [TradeItInstrumentOrderCapabilities] ?? []
                return existingAccount
            } else {
                return TradeItLinkedBrokerAccount(
                    linkedBroker: self,
                    accountName: account.name,
                    accountNumber: account.accountNumber,
                    accountIndex: account.accountIndex,
                    accountBaseCurrency: account.accountBaseCurrency,
                    balance: nil,
                    fxBalance: nil,
                    positions: [],
                    orderCapabilities: account.orderCapabilities as? [TradeItInstrumentOrderCapabilities] ?? [],
                    isEnabled: true
                )
            }
        }

        self.accounts = newLinkedBrokerAccounts
        self.accountsLastUpdated = Date()
    }
}
