import UIKit

class TradeItOrdersTableViewManager: NSObject, UITableViewDelegate, UITableViewDataSource {

    private var _table: UITableView?
    private var refreshControl: UIRefreshControl?
    
    private static let ORDER_CELL_HEIGHT = 50
    private static let SECTION_HEADER_HEIGHT = 15
    private static let OPEN_ORDERS_SECTION = 0
    private static let FILLED_ORDERS_SECTION  = 1
    private static let OTHER_ORDERS_SECTION = 2
    
    var ordersTable: UITableView? {
        get {
            return _table
        }
        
        set(newTable) {
            if let newTable = newTable {
                newTable.dataSource = self
                newTable.delegate = self
                addRefreshControl(toTableView: newTable)
                _table = newTable
            }
        }

    }
    
    private var orderSectionPresenters: [OrderSectionPresenter] = []
    
    weak var delegate: TradeItOrdersTableDelegate?
    
    func initiateRefresh() {
        self.refreshControl?.beginRefreshing()
        self.delegate?.refreshRequested(
            onRefreshComplete: {
                self.refreshControl?.endRefreshing()
            }
        )
    }
    
    func updateOrders(_ orders: [TradeItOrderStatusDetails]) {
        let openOrders = orders.filter { ["PENDING", "OPEN", "PART_FILLED", "PENDING_CANCEL"].contains($0.orderStatus ?? "") }
        let filledOrders = orders.filter { ["FILLED"].contains($0.orderStatus ?? "") }
        let otherOrders = orders.filter { ["CANCELED", "REJECTED", "NOT_FOUND", "EXPIRED"].contains($0.orderStatus ?? "") }
        self.orderSectionPresenters = [
            OrderSectionPresenter(orders: openOrders),
            OrderSectionPresenter(orders: filledOrders),
            OrderSectionPresenter(orders: otherOrders)
        ]
        self.ordersTable?.reloadData()
    }
    
    // MARK: UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case TradeItOrdersTableViewManager.OPEN_ORDERS_SECTION:
            return "Open Orders (Past 60 Days)"
        case TradeItOrdersTableViewManager.FILLED_ORDERS_SECTION:
            return "Filled Orders (Today)"
        case TradeItOrdersTableViewManager.OTHER_ORDERS_SECTION:
            return "Other Orders (Today)"
        default:
            return "Unknown"
        }
    }
    
    // MARK: UITableViewDataSource
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return self.orderSectionPresenters[indexPath.section].cell(forTableView: tableView, andRow: indexPath.row)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let orderSectionPresenter = self.orderSectionPresenters[safe: section] else { return 0 }
        return orderSectionPresenter.numberOfRows()
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.orderSectionPresenters.count
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return CGFloat(TradeItOrdersTableViewManager.ORDER_CELL_HEIGHT)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return CGFloat(TradeItOrdersTableViewManager.ORDER_CELL_HEIGHT)
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return CGFloat(TradeItOrdersTableViewManager.SECTION_HEADER_HEIGHT)
    }
    
    // MARK: Private
    
    func addRefreshControl(toTableView tableView: UITableView) {
        let refreshControl = UIRefreshControl()
        refreshControl.attributedTitle = NSAttributedString(string: "Refreshing...")
        refreshControl.addTarget(
            self,
            action: #selector(initiateRefresh),
            for: UIControlEvents.valueChanged
        )
        TradeItThemeConfigurator.configure(view: refreshControl)
        tableView.addSubview(refreshControl)
        self.refreshControl = refreshControl
    }

}

fileprivate class OrderSectionPresenter {
    let orders: [TradeItOrderStatusDetails]
    
    init(orders: [TradeItOrderStatusDetails]) {
        self.orders = orders
    }
    
    func numberOfRows() -> Int {
        return self.orders.flatMap { $0.orderLegs }.count
    }
    
    func cell(forTableView tableView: UITableView, andRow row: Int) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "TRADE_IT_ORDER_CELL_ID") as? TradeItOrderTableViewCell else {
            return UITableViewCell()
        }
        cell.populate(withOrder: self.orders[row])
        return cell
    }
}


protocol TradeItOrdersTableDelegate: class {
    func refreshRequested(onRefreshComplete: @escaping () -> Void)
}
