import UIKit
import MBProgressHUD
import PromiseKit

class TradeItPortfolioAccountDetailsViewController: TradeItViewController, TradeItPortfolioAccountDetailsTableDelegate {
    var tableViewManager: TradeItPortfolioAccountDetailsTableViewManager!
    var tradingUIFlow = TradeItTradingUIFlow()
    let viewControllerProvider = TradeItViewControllerProvider()
    var alertManager = TradeItAlertManager()
    var linkedBrokerAccount: TradeItLinkedBrokerAccount?

    @IBOutlet weak var table: UITableView!
    @IBOutlet weak var adContainer: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let linkedBrokerAccount = self.linkedBrokerAccount else {
            preconditionFailure("TradeItIosTicketSDK ERROR: TradeItPortfolioViewController loaded without setting linkedBrokerAccount.")
        }

        self.tableViewManager = TradeItPortfolioAccountDetailsTableViewManager(account: linkedBrokerAccount)
        self.navigationItem.title = linkedBrokerAccount.linkedBroker?.brokerLongName

        self.tableViewManager.delegate = self
        self.tableViewManager.table = self.table

        self.tableViewManager.initiateRefresh()

        TradeItSDK.adService.populate?(
            adContainer: self.adContainer,
            rootViewController: self,
            pageType: .portfolio,
            position: .bottom,
            broker: linkedBrokerAccount.linkedBroker?.brokerName,
            symbol: nil,
            instrumentType: nil,
            trackPageViewAsPageType: true
        )
    }
    
    @IBAction func activityTapped(_ sender: Any) {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        
        let ordersAction = UIAlertAction(title: "Orders", style: .default, handler: orderActionWasTapped)
        let tradeAction = UIAlertAction(title: "Trade", style: .default, handler: tradeActionWasTapped)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(ordersAction)
        alertController.addAction(tradeAction)
        alertController.addAction(cancelAction)
        
        self.present(alertController, animated: true, completion: nil)
    }

    func refreshRequested(onRefreshComplete: @escaping () -> Void) {
        guard let linkedBrokerAccount = self.linkedBrokerAccount, let linkedBroker = linkedBrokerAccount.linkedBroker else {
            preconditionFailure("TradeItIosTicketSDK ERROR: TradeItPortfolioViewController loaded without setting linkedBrokerAccount.")
        }

        let authenticatePromise = Promise { fulfill, reject in
            linkedBroker.authenticateIfNeeded(
                onSuccess: fulfill,
                onSecurityQuestion: { securityQuestion, answerSecurityQuestion, cancelSecurityQuestion in
                    self.alertManager.promptUserToAnswerSecurityQuestion(
                        securityQuestion,
                        onViewController: self,
                        onAnswerSecurityQuestion: answerSecurityQuestion,
                        onCancelSecurityQuestion: cancelSecurityQuestion
                    )
                },
                onFailure: reject
            )
        }

        let accountOverviewPromise = Promise<Void> { fulfill, reject in
            linkedBrokerAccount.getAccountOverview(
                cacheResult: true,
                onSuccess: { _ in
                    self.tableViewManager.updateAccount(withAccount: linkedBrokerAccount)
                    fulfill()
                },
                onFailure: { error in
                    self.tableViewManager.updateAccount(withAccount: nil)
                    reject(error)
                }
            )
        }

        let positionsPromise = Promise<Void> { fulfill, reject in
            linkedBrokerAccount.getPositions(
                onSuccess: { positions in
                    self.tableViewManager.updatePositions(withPositions: positions)
                    fulfill()
                },
                onFailure: { error in
                    self.tableViewManager.updateAccount(withAccount: nil)
                    reject(error)
                }
            )
        }

        firstly {
            authenticatePromise
        }.then { _ in
            return when(fulfilled: accountOverviewPromise, positionsPromise)
        }.catch { error in
            print(error)
        }.always {
            onRefreshComplete()
        }
    }

    // MARK: Private

    private func tradeActionWasTapped(alert: UIAlertAction!) {
        let order = provideOrder(forPortFolioPosition: nil, account: self.linkedBrokerAccount, orderAction: nil)
        self.tradingUIFlow.presentTradingFlow(fromViewController: self, withOrder: order)
    }
    
    private func orderActionWasTapped(alert: UIAlertAction!) {
        guard let ordersViewController = self.viewControllerProvider.provideViewController(forStoryboardId: .ordersView) as? TradeItOrdersViewController else {
            return
        }
        ordersViewController.linkedBrokerAccount = self.linkedBrokerAccount
        self.navigationController?.pushViewController(ordersViewController, animated: true)
    }
    
    private func provideOrder(forPortFolioPosition portfolioPosition: TradeItPortfolioPosition?,
                                                   account: TradeItLinkedBrokerAccount?,
                                                   orderAction: TradeItOrderAction?) -> TradeItOrder {
        let order = TradeItOrder()
        order.linkedBrokerAccount = account
        if let portfolioPosition = portfolioPosition {
            order.symbol = TradeItPortfolioEquityPositionPresenter(portfolioPosition).getFormattedSymbol()
        }
        order.action = orderAction ?? TradeItOrderActionPresenter.DEFAULT
        return order
    }

    // MARK: TradeItPortfolioAccountDetailsTableDelegate

    func tradeButtonWasTapped(forPortFolioPosition portfolioPosition: TradeItPortfolioPosition?, orderAction: TradeItOrderAction?) {
        let order = self.provideOrder(forPortFolioPosition: portfolioPosition, account: portfolioPosition?.linkedBrokerAccount, orderAction: orderAction)
        self.tradingUIFlow.presentTradingFlow(fromViewController: self, withOrder: order)
    }
}
