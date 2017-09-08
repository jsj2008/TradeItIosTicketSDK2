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
        self.orderSectionPresenters = []
        
        self.orderSectionPresenters.append(OrderSectionPresenter(orders: [], title: "Open Orders (Past 60 Days)"))
        let openOrders = orders.filter { ["PENDING", "OPEN", "PART_FILLED", "PENDING_CANCEL"].contains($0.orderStatus ?? "") }
        let splitedOpenOrdersArray = getSplittedOrdersArray(orders: openOrders)
        buildOrderSectionPresentersFrom(splitedOrdersArray: splitedOpenOrdersArray)
        
        self.orderSectionPresenters.append(OrderSectionPresenter(orders: [], title: "Filled Orders (Today)"))
        let filledOrders = orders.filter { ["FILLED"].contains($0.orderStatus ?? "") }
        let splitedFilledOrdersArray = getSplittedOrdersArray(orders: filledOrders)
        buildOrderSectionPresentersFrom(splitedOrdersArray: splitedFilledOrdersArray)
        
        self.orderSectionPresenters.append(OrderSectionPresenter(orders: [], title: "Other Orders (Today)"))
        let otherOrders = orders.filter { ["CANCELED", "REJECTED", "NOT_FOUND", "EXPIRED"].contains($0.orderStatus ?? "") }
        let splitedOtherOrdersArray = getSplittedOrdersArray(orders: otherOrders)
        buildOrderSectionPresentersFrom(splitedOrdersArray: splitedOtherOrdersArray)
        
        self.ordersTable?.reloadData()
    }
    
    // MARK: UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.orderSectionPresenters[section].title
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
    
    private func addRefreshControl(toTableView tableView: UITableView) {
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
    
    /**
     * This is to split orders in order to have a specific section for group orders
    **/
    private func getSplittedOrdersArray(orders: [TradeItOrderStatusDetails]) -> [[TradeItOrderStatusDetails]]{
        return orders.reduce([[]], { splittedArrays, order in
            var splittedArraysTmp = splittedArrays
            let lastResult: [TradeItOrderStatusDetails] = splittedArrays[(splittedArrays.endIndex - 1)]
            
            let groupOrderType = order.groupOrderType ?? ""
            
            if groupOrderType.isEmpty && !lastResult.contains(order) { // this is not a group order, we can append the order
                splittedArraysTmp[(splittedArraysTmp.endIndex - 1)].append(order)
                return splittedArraysTmp
            } else { // This is a group order or the begining of a new array
                splittedArraysTmp.append([order])
                return splittedArraysTmp
            }
        })
    }
    
    private func buildOrderSectionPresentersFrom(splitedOrdersArray: [[TradeItOrderStatusDetails]]) {
        splitedOrdersArray.forEach { splittedOrders in
            var title = ""
            if let groupOrder = (splittedOrders.filter { $0.groupOrderType != "" && $0.groupOrderType != nil }).first
                , let groupOrderType = groupOrder.groupOrderType {
                title = groupOrderType.lowercased().capitalized.replacingOccurrences(of: "_", with: " ")
            }
            self.orderSectionPresenters.append(
                OrderSectionPresenter(
                    orders: splittedOrders,
                    title: title
                )
            )
        }
    }

}

fileprivate class OrderSectionPresenter {
    let orders: [TradeItOrderStatusDetails]
    let title: String
    
    init(orders: [TradeItOrderStatusDetails], title: String) {
        self.orders = orders
        self.title = title
    }
    
    func numberOfRows() -> Int {
        return self.orders.flatMap { $0.orderLegs ?? [] }.count
    }
    
    func cell(forTableView tableView: UITableView, andRow row: Int) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "TRADE_IT_ORDER_CELL_ID") as? TradeItOrderTableViewCell
            , let orderLeg = (self.orders.flatMap { $0.orderLegs ?? [] }) [safe: row]
            , let order = (self.orders.filter { $0.orderLegs?.contains(orderLeg) ?? false }).first
        else {
            return UITableViewCell()
        }
        
        cell.populate(withOrder: order, andOrderLeg: orderLeg)
        return cell
    }
}


protocol TradeItOrdersTableDelegate: class {
    func refreshRequested(onRefreshComplete: @escaping () -> Void)
}
