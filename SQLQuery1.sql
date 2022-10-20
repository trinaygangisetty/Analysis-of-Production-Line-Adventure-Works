-- This is Script for SelectTopNRows command in SSMS. We can represent the column names in squarebrackets or without them.
SELECT TOP (1000) [ProductID]
      ,[Name]
      ,[ProductNumber]
      ,[MakeFlag]
      ,[FinishedGoodsFlag]
      ,[Color]
      ,[SafetyStockLevel]
      ,[ReorderPoint]
      ,[StandardCost]
      ,[ListPrice]
      ,[Size]
      ,[SizeUnitMeasureCode]
      ,[WeightUnitMeasureCode]
      ,[Weight]
      ,[DaysToManufacture]
      ,[ProductLine]
      ,[Class]
      ,[Style]
      ,[ProductSubcategoryID]
      ,[ProductModelID]
      ,[SellStartDate]
      ,[SellEndDate]
      ,[DiscontinuedDate]
      ,[rowguid]
      ,[ModifiedDate]
  FROM [AdventureWorks2017].[Production].[Product];


SELECT *
FROM AdventureWorks2017.Production.Product
-------------------------------------------------------------------------------------------------------------------------------------------

-- DATA CLEANSING AND COLUMNS TRANSFORMATION.

 ALTER TABLE AdventureWorks2017.Production.Product
 ADD SellingStartDate Date;

 UPDATE AdventureWorks2017.Production.Product
 SET SellingStartDate = CONVERT(Date,SellStartDate);

 ALTER TABLE AdventureWorks2017.Production.Product
 ADD SellingEndDate Date;

 UPDATE AdventureWorks2017.Production.Product
 SET SellingEndDate = CONVERT(DATE,SellEndDate);

 SELECT DISTINCT DiscontinuedDate
 FROM AdventureWorks2017.Production.Product ;
 --Entire column is Null. None of the Products were discontinued. So not transforming the column and leaving as such.

 ------------------------------------------------------------------------------------------------------------------------------------------------------------------

 --PRODUCT - PRODUCT_SUBCATEGORY - PRODUCT_CATEGORY - LINE

 select *
 from AdventureWorks2017.Production.ProductCategory;
 select * 
 from AdventureWorks2017.Production.ProductSubcategory;

--COUNT OF TYPES EACH CATEGORY HAS

 select pc.ProductCategoryID, 
        pc.Name as categoryName, 
		ps.Name as subCategoryName,
		ROW_NUMBER() over(partition by pc.Name order by ps.Name) as categoryCount
 from AdventureWorks2017.Production.ProductCategory pc
 inner join AdventureWorks2017.Production.ProductSubCategory ps
 on pc.ProductCategoryID = ps.ProductCategoryID
 order by 1;

 --COUNT OF TYPES EACH SUBCATEGORY HAS 

 select pc.ProductCategoryID, 
        pc.Name as categoryName, 
        ps.Name as subCategoryName,
        p.Name as productName,
	ROW_NUMBER() OVER(partition by pc.Name order by ps.Name) as categoryCount,
	ROW_NUMBER() OVER(partition by ps.Name order by ps.name) as subCategoryCount
 from AdventureWorks2017.Production.ProductCategory pc
 inner join AdventureWorks2017.Production.ProductSubCategory ps
 on pc.ProductCategoryID = ps.ProductCategoryID
 inner join AdventureWorks2017.Production.Product p
 on ps.ProductSubcategoryID = p.ProductSubcategoryID
 order by 1;

 --CREATE TEMPORARY TABLE FOR STORING THE ABOVE RESULT

 DROP TABLE IF EXISTS #categoryTypes
 CREATE TABLE #categoryTypes(
       categoryId int,
       categoryName varchar(50),
       subCategoryName varchar(50),
       categoryCount int
	)

INSERT INTO #categoryTypes 
SELECT * 
FROM ( select pc.ProductCategoryID, 
        pc.Name as categoryName, 
        ps.Name as subCategoryName,
	ROW_NUMBER() over(partition by pc.Name order by ps.Name) as categoryCount
 from AdventureWorks2017.Production.ProductCategory pc
 inner join AdventureWorks2017.Production.ProductSubCategory ps
 on pc.ProductCategoryID = ps.ProductCategoryID
 ) AS temp;

 SELECT * 
 FROM #categoryTypes
 order by 1;
 
 --PIVOT OPERATOR to count number of subcategories each category has in a very readable format.

 select *
 from
 (
 select categoryName, subCategoryName
 from #categoryTypes
 ) as sourceTable
 pivot
 (
   count(subCategoryName)
   for
   categoryName IN ([Bikes],[Components],[Clothing],[Accessories])
 ) as PivotTable;

 --Products which do not have any subcategory id

 SELECT *
 FROM AdventureWorks2017.Production.Product
 WHERE ProductSubcategoryID IS NULL;  --209 products are not classified into any category.
 
 ----------------------------------------------------------------------------------------------------------------------------------------------------------

 --PRODUCT - PRODUCT_INVENTORY - LINE

 SELECT *
 FROM AdventureWorks2017.Production.ProductInventory;

 SELECT ProductID, sum(Quantity) as Qty
 FROM AdventureWorks2017.Production.ProductInventory
 GROUP BY ProductID
 order by ProductID; --432 products found

 SELECT DISTINCT ProductID
FROM AdventureWorks2017.Production.Product
order by ProductID;  --504 products found

--products which do not have any stock in inventory

SELECT ProductID
from AdventureWorks2017.Production.Product
EXCEPT
SELECT productID
from AdventureWorks2017.Production.ProductInventory; --72 products returned (432 + 72 = 504) 

--Looking if products with no inventory are stopped being sold.

WITH cte(productID) as(
 SELECT ProductID
 from AdventureWorks2017.Production.Product
 EXCEPT
 SELECT productID
 from AdventureWorks2017.Production.ProductInventory
)

select p.ProductID, Name, SellEndDate 
from AdventureWorks2017.Production.Product p
inner join cte c
on p.ProductID = c.productID;  -- there is no direct relationship since some of products still do not have saleEndDate and are being sold.

-- to check which products are in safety stock level and which are not. SAFE(with in level), DANGER(not in safety level)
-- if safetyline indicator indicates danger, then further checking for restocking point if it is time to restock.

WITH CTE AS (
 SELECT ProductID, sum(Quantity) as Qty
 FROM AdventureWorks2017.Production.ProductInventory
 GROUP BY ProductID
 ),

 CTE2 AS (
 select p.productID,
        q.Qty as QtyAvailable,
        P.SafetyStockLevel,
        CASE WHEN q.qty >= p.SafetyStockLevel THEN 'SAFE'
	     ELSE 'DANGER'
             END AS SafetyLineIndicator
 from AdventureWorks2017.Production.Product p
 inner join CTE q
 on p.ProductID = q.ProductID
 )

 SELECT q.*,
        p.ReorderPoint,
        IIF(SafetyLineIndicator = 'SAFE', 'N/A', IIF(q.QtyAvailable > p.ReorderPoint, 'IT IS OKAY', 'TIME TO RESTOCK!!')) AS RestockIndicator
from AdventureWorks2017.Production.Product p
inner join CTE2 q
on p.ProductID = q.ProductID;

----------------------------------------------------------------------------------------------------------------------------------------------------------

--PRODUCT - WORK_ORDER - WORK_ORDER_ROUTING - LOCATION - LINE  (AND) WORK_ORDER - SCRAP_REASON - LINE

SELECT *
FROM AdventureWorks2017.Production.WorkOrder;

SELECT *
FROM AdventureWorks2017.Production.WorkOrderRouting
order by 1;

SELECT distinct ProductID
FROM AdventureWorks2017.Production.WorkOrder; -- only 238 products have work order related records.

-- TOP N products and its details which are ordered most times.

declare @n int;
set @n = 10;

select TOP (@n) *
from 
(
select TOP (@n) ProductID,
       sum(OrderQty) as orderQty, 
       sum(StockedQty) as stockedQty, 
       sum(ScrappedQty) as scrappedQty
from AdventureWorks2017.Production.WorkOrder
group by ProductID
order by 2 desc
) temp
inner join AdventureWorks2017.Production.Product p
on temp.ProductID = p.ProductID;


-- Scrapped quantity

WITH CTE AS (
select temp.*,
       ROUND(CONVERT(DECIMAL(18,2),(1.0 * scrappedQty / orderQty) * 100.0), 2) as scrappedPercentage
from(
select ProductID,
       sum(OrderQty) as orderQty, 
       sum(StockedQty) as stockedQty, 
       sum(ScrappedQty) as scrappedQty
from AdventureWorks2017.Production.WorkOrder
group by ProductID
) as temp
)

SELECT *,
       CASE WHEN scrappedPercentage > 0.6 THEN 'HIGH LOSS'
	    WHEN scrappedPercentage > 0.3 THEN 'MEDIUM LOSS'
	    WHEN scrappedPercentage > 0.0 THEN 'LOW LOSS'
	    ELSE 'NO LOSS' 
	    END AS lossIndicator
FROM CTE
order by scrappedPercentage desc;

-- rolling sum of scrapped items per product

select WorkOrderID,
       ProductID,
       OrderQty,
       StockedQty,
       ScrappedQty,
       wo.ScrapReasonID,
       Name,
       SUM(scrappedQty) over(partition by ProductID order by ProductID ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as rollingSum
from AdventureWorks2017.Production.WorkOrder wo
inner join AdventureWorks2017.Production.ScrapReason scr
on wo.ScrapReasonID = scr.ScrapReasonID

-- more number of items are scrapped due to which reason?

select wo.ScrapReasonID, Name, sum(scrappedQty) as totalScrappedQty
from AdventureWorks2017.Production.WorkOrder wo
inner join AdventureWorks2017.Production.ScrapReason scr
on wo.ScrapReasonID = scr.ScrapReasonID
GROUP BY wo.ScrapReasonID, Name
order by sum(scrappedQty) DESC

-- efficiency and total days taken after due date to deliver products.

select *, DATEDIFF(day, DueDate, EndDate) as extraDays
from AdventureWorks2017.Production.WorkOrder;

ALTER TABLE AdventureWorks2017.Production.WorkOrder
ADD extraDays int;

UPDATE AdventureWorks2017.Production.WorkOrder
SET extraDays = DATEDIFF(day, DueDate, EndDate);

WITH CTE AS (
select ProductID,
       sum(extraDays) as extraDays,
       sum(days_required) as totalDaysRequired,
       sum(days_taken) as totalDaysTaken
from (select *,
             DATEDIFF( day, StartDate, DueDate ) AS days_required,
             DATEDIFF( day, StartDate, EndDate ) AS days_taken
      from AdventureWorks2017.Production.WorkOrder) as temp
Group by ProductID)

SELECT *,
      ROUND(CONVERT(DECIMAL(18,2),(1.0 * totalDaysRequired / totalDaysTaken)),2) * 100 as efficiency
from CTE
order by efficiency desc, productID asc;

-- how many work orders are taking place in each location for each productID (work_order_routing - location)

select ProductID, loc.LocationID, Name, count(*) AS noOfOrders
from AdventureWorks2017.Production.Location loc
inner join AdventureWorks2017.Production.WorkOrderRouting wor
on loc.LocationID = wor.LocationID
group by ProductID, loc.LocationID, Name
order by 4 desc, 1 asc;

-- rolling count of operation sequence for each product id

select p.ProductID,
       OperationSequence,
       count(operationSequence) over(partition by wo.productId order by wo.ProductId ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rollingCountOfOperation
from AdventureWorks2017.Production.Product p
left join AdventureWorks2017.Production.WorkOrder wo
on p.ProductID = wo.ProductID
left join AdventureWorks2017.Production.WorkOrderRouting wor
on wo.WorkOrderID = wor.WorkOrderID;

-- products which do not have any operation sequence associated with them.

select distinct p.ProductID  
from AdventureWorks2017.Production.Product p
left join AdventureWorks2017.Production.WorkOrder wo
on p.ProductID = wo.ProductID
left join AdventureWorks2017.Production.WorkOrderRouting wor
on wo.WorkOrderID = wor.WorkOrderID
where OperationSequence IS NULL;

-- No.of products stored in each location in each shelf with rolling count and total count.

SELECT *,
       SUM(totalProducts) over(Partition by locationId order by totalProducts desc rows between unbounded preceding and current row) as rollingProductsCount,
       SUM(totalProducts) over(Partition by locationId order by totalProducts desc rows between unbounded preceding and unbounded following) as TotalProductsCount
FROM(
select loc.LocationID, loc.Name, Shelf, SUM(Quantity) as TotalProducts
from AdventureWorks2017.Production.Location loc
inner join AdventureWorks2017.Production.ProductInventory inv
on loc.LocationID = inv.LocationID
group by loc.LocationID, Name, Shelf
) as temp
order by temp.LocationID , TotalProducts desc; 

-- no of products contained in an each operation sequence (1 to 7)

WITH CTE AS 
(
select operationSequence,
       count(ProductID) over(partition by operationSequence order by operationSequence) as noOfProductsInEachOpSeq
from(
select OperationSequence,
       ProductID
from AdventureWorks2017.Production.WorkOrderRouting
group by OperationSequence, ProductID
) as temp
)
SELECT *
FROM CTE 
GROUP BY OperationSequence, noOfProductsInEachOpSeq
order by OperationSequence;

----------------------------------------------------------------------------------------------------------------------------------------------------------------

-- PRODUCT - PRODUCT_LIST_PRICE_HISTORY - LINE

select *
from AdventureWorks2017.Production.Product P
LEFT JOIN
AdventureWorks2017.Production.ProductListPriceHistory PL
on P.ProductID = PL.ProductID;

-- calculate rolling differences in price history of products.

WITH CTE AS (
select *,
       IIF(PreviousPrice is Null, ListPrice, PreviousPrice) as modifiedPreviousPrice
from(
select *,
       LAG(ListPrice, 1) over (partition by productID order by productID) as PreviousPrice
FROM AdventureWorks2017.Production.ProductListPriceHistory
) as temp
)
SELECT ProductID, StartDate, EndDate, ListPrice, modifiedPreviousPrice,
       listPrice - modifiedPreviousPrice as priceIncrease,
       (ListPrice - modifiedPreviousPrice) / modifiedPreviousPrice * 100 as PercentageIncreaseInPrice
From CTE;

-- selecting only aggregated records with all information (latest price records) from the above table.

WITH CTE AS (
select *,
       IIF(PreviousPrice is Null, ListPrice, PreviousPrice) as modifiedPreviousPrice
from(
select *,
       LAG(ListPrice, 1) over (partition by productID order by productID) as PreviousPrice
FROM AdventureWorks2017.Production.ProductListPriceHistory
) as temp
),
CTE2 AS (
SELECT ProductID, StartDate, EndDate, ListPrice, modifiedPreviousPrice,
       listPrice - modifiedPreviousPrice as priceIncrease,
       (ListPrice - modifiedPreviousPrice) / modifiedPreviousPrice * 100 as PercentageIncreaseInPrice
From CTE 
),
CTE3 AS (
SELECT *,
       ROW_NUMBER() OVER(PARTITION BY productID order by PercentageIncreaseInPrice desc) as ranking 
FROM CTE2
),
CTE4 AS (
SELECT ProductID , StartDate, EndDate, 
       ListPrice , modifiedPreviousPrice , PriceIncrease, 
       PercentageIncreaseInPrice
FROM  CTE3 
WHERE ranking = 1
)
SELECT P.ProductID AS ProductProductID,
       C.ProductID AS ListPriceProductID,
       StartDate, 
       EndDate, 
       C.ListPrice AS ListPricePrice,
       P.ListPrice AS ProductListPrice,
       modifiedPreviousPrice as PreviousPrice, 
       PriceIncrease, 
       PercentageIncreaseInPrice
FROM AdventureWorks2017.Production.Product P
LEFT JOIN CTE4 C
ON P.ProductID = C.ProductID
order by PercentageIncreaseInPrice desc, P.ProductID asc;

-----------------------------------------------------------------------------------------------------------------------------------------------------------------

-- PRODUCT - PRODUCT_COST_HISTORY - LINE

select *
from AdventureWorks2017.Production.ProductCostHistory;

-- The table is very similar to product list price history and can be solved using similar approach as product list price history.


WITH CTE AS (
select *,
       IIF(PreviousCost is Null, StandardCost, PreviousCost) as modifiedPreviousPrice
from(
select *,
       LAG(StandardCost, 1) over (partition by productID order by productID) as PreviousCost
FROM AdventureWorks2017.Production.ProductCostHistory
) as temp
),
CTE2 AS (
SELECT ProductID, StartDate, EndDate, StandardCost, modifiedPreviousPrice,
       StandardCost - modifiedPreviousPrice as priceIncrease,
       (StandardCost - modifiedPreviousPrice) / modifiedPreviousPrice * 100 as PercentageIncreaseInPrice
From CTE 
),
CTE3 AS (
SELECT *,
       ROW_NUMBER() OVER(PARTITION BY productID order by PercentageIncreaseInPrice desc) as ranking 
FROM CTE2
),
CTE4 AS (
SELECT ProductID , StartDate, EndDate, 
       StandardCost , modifiedPreviousPrice , PriceIncrease, 
       PercentageIncreaseInPrice
FROM  CTE3 
WHERE ranking = 1
)
SELECT P.ProductID AS ProductProductID,
       C.ProductID AS ListPriceProductID,
       StartDate, 
       EndDate, 
       C.StandardCost AS CostPricePrice,
       P.StandardCost AS ProductCostPrice,
       modifiedPreviousPrice as PreviousPrice, 
       PriceIncrease, 
       PercentageIncreaseInPrice
FROM AdventureWorks2017.Production.Product P
LEFT JOIN CTE4 C
ON P.ProductID = C.ProductID
order by PercentageIncreaseInPrice desc, P.ProductID asc;

----------------------------------------------------------------------------------------------------------------------------------------------------------------

-- PRODUCT - PRODUCT_REVIEW - LINE

select *
from AdventureWorks2017.Production.ProductReview; -- only 3 products have been given reviews by people.
                                                 -- The table contains very less information and it is not completely filled.
												 -- Analysing only with the available information.

-- most reviewed product with total average rating and rolling average rating. ( covered two scenarios in a single query )

WITH CTE AS (
SELECT p.ProductID,
       count(p.productID) over(partition by p.productID order by p.productID) as no_of_times_product_reviewed,
       pr.ReviewerName, pr.Rating, p.Name, p.ProductNumber,
       AVG(Rating) over(partition by p.productID order by p.productID) as averageRating, 
       AVG(Rating) over(partition by p.productID order by p.productID rows between unbounded preceding and current row) as rollingAverageRating
from AdventureWorks2017.Production.ProductReview pr
inner join AdventureWorks2017.Production.Product p
on pr.ProductID = p.ProductID)
SELECT *
FROM CTE
WHERE no_of_times_product_reviewed = (SELECT max(no_of_times_product_reviewed) from CTE);

-------------------------------------------------------------------------------------------------------------------------------------------------------------

-- PRODUCT - TRANSACTION_HISTORY - LINE

select distinct ProductID
from AdventureWorks2017.Production.TransactionHistory; -- Transaction history is available for 441 products out of 504 total products.

select * 
from AdventureWorks2017.Production.TransactionHistory; -- The table contains for three types of order transactions.
                                                       -- W - WorkOrder; S - SalesOrder; P - PurchaseOrder

-- total different types of transactions made.

SELECT TransactionType, count(transactionType) as noOfTransactionsMade,
       CASE WHEN TransactionType = 'S' THEN 'Sales Order'
	    WHEN TransactionType = 'W' THEN 'Work Order'
	    ELSE 'Purchase Order' 
	    END AS TransactionName,
	   SUM(Quantity) as totalQuantityOrdered
From AdventureWorks2017.Production.TransactionHistory
group by TransactionType
order by 2 desc;

-- total money transaction made across three categories and also products partitioned by categories.

ALTER TABLE AdventureWorks2017.Production.TransactionHistory
DROP COLUMN Amount;

ALTER TABLE AdventureWorks2017.Production.TransactionHistory
ADD Amount float;

UPDATE AdventureWorks2017.Production.TransactionHistory
SET Amount = Quantity * ActualCost;

SELECT *,
       SUM(Amount) over(partition by productID, transactionType order by productID rows between unbounded preceding and unbounded following) as IndividualProductIDTransaction,
       SUM(Amount) over(partition by transactionType order by productID rows between unbounded preceding and unbounded following) as categoryTotalTransaction	   
FROM AdventureWorks2017.Production.TransactionHistory
order by TransactionType, ProductID;

-- checking sales order transaction to find out the overall sales made for products.

SELECT *,
       ListPrice * totalQuantityOfSales as TotalSales
from(
SELECT p.ProductID, p.ListPrice ,sum(quantity) as totalQuantityOfSales
FROM AdventureWorks2017.Production.Product p
inner join AdventureWorks2017.Production.TransactionHistory tr
on p.ProductID = tr.ProductID
WHERE TransactionType = 'S'
group by p.ProductID, p.ListPrice
) as temp
order by Totalsales desc, productID;

------------------------------------------------------------------------------------------------------------------------------------------------------------

-- PRODUCT (PRODUCTION) - SHOPPING_CART (SALES) - LINE

Select *
from AdventureWorks2017.Sales.ShoppingCartItem;  -- As per Analysis This table has been created only for the representational purposes.
                                                 -- It had only a very few records.
										-- It is not linked up to any other table other than production.product as per ERD.
										-- This table can be used to analyse the purchase patterns and trends for the products.
									        -- And also the product which has more tendency to be sold or can be bought can be found out.

-- Statistics of products that are present in the shopping carts of customers.

SELECT *, DENSE_RANK() OVER(order by profitOfCart desc) AS rankOfCartWithmostProfit
from(
Select ShoppingCartID, SUM(Quantity * StandardCost) as CostPriceOfCart,
       SUM(Quantity * ListPrice) as SellingPriceOfCart,
       (SUM(Quantity * ListPrice) - SUM(Quantity * StandardCost)) as ProfitOfCart,
       COUNT(pro.productID) as NoOfProductTypesInCart,
       COUNT(productLine) as TotalProductLinesInCart,
       COUNT(color) as TotalColorsPerCart,
       SUM(quantity) as TotalQuantityOfCart
from AdventureWorks2017.Sales.ShoppingCartItem Sh
inner join AdventureWorks2017.Production.Product Pro
on Pro.ProductID = Sh.ProductID
group by ShoppingCartID
) as temp
order by ProfitOfCart desc;

-------------------------------------------------------------------------------------------------------------------------------------------------------------

-- PRODUCT - PRODUCT_PRODUCT_PHOTO - PRODUCT_PHOTO - LINE 

SELECT P.ProductID, PPP.*, PP.*
from AdventureWorks2017.Production.ProductPhoto PP
Inner join AdventureWorks2017.Production.ProductProductPhoto PPP
on PP.ProductPhotoID = PPP.ProductPhotoID
Inner join AdventureWorks2017.Production.Product P
on PPP.ProductID = P.ProductID
order by P.ProductID;   -- This tables were used to store images og their respective products in both small format as well as large format.

--------------------------------------------------------------------------------------------------------------------------------------------------------------

-- PRODUCT - PRODUCT_MODEL - PRODUCT_MODEL_PRODUCT_DESCRIPTION_CULTURE - PRODUCT_DESCRIPTION - CULTURE - LINE

SELECT PM.ProductModelID,
       P.ProductID,
       P.Name AS ProductName,
       P.ProductNumber,
       PD.ProductDescriptionID,
       PD.Description,
       PMPD.CultureID,
       C.Name AS CultureName,
       PM.Name AS ProductModelName,
       PM.CatalogDescription,
       PM.Instructions
FROM AdventureWorks2017.Production.ProductModelProductDescriptionCulture PMPD
INNER JOIN AdventureWorks2017.Production.ProductDescription PD
ON PMPD.ProductDescriptionID = PD.ProductDescriptionID
INNER JOIN AdventureWorks2017.Production.Culture C
ON PMPD.CultureID = C.CultureID
INNER JOIN AdventureWorks2017.Production.ProductModel PM
ON PMPD.ProductModelID = PM.ProductModelID
INNER JOIN AdventureWorks2017.Production.Product P
ON PM.ProductModelID = P.ProductModelID

         -- The result of above query can be inserted into a temporary table (which lasts for the total instance of querying until the window is switched off)
	 -- Further the Temporary table can be queried in order to get the required results that can be either for some particular culture or for some product etc.


DROP TABLE IF EXISTS #PMPDC
CREATE TABLE #PMPDC( 
       ProductModelID int,
       ProductID int,
       ProductName varchar(50),
       ProductNumber varchar(50),
       ProductDescriptionID int,
       Description nvarchar(500),
       CultureID varchar(50),
       CultureName varchar(50),
       ProductModelName varchar(50),
       CatalogDescription xml,
       Instructions xml
	)

INSERT INTO #PMPDC
SELECT * 
FROM ( SELECT PM.ProductModelID,
       P.ProductID,
       P.Name AS ProductName,
       P.ProductNumber,
       PD.ProductDescriptionID,
       PD.Description,
       PMPD.CultureID,
       C.Name AS CultureName,
       PM.Name AS ProductModelName,
       PM.CatalogDescription,
       PM.Instructions
FROM AdventureWorks2017.Production.ProductModelProductDescriptionCulture PMPD
INNER JOIN AdventureWorks2017.Production.ProductDescription PD
ON PMPD.ProductDescriptionID = PD.ProductDescriptionID
INNER JOIN AdventureWorks2017.Production.Culture C
ON PMPD.CultureID = C.CultureID
INNER JOIN AdventureWorks2017.Production.ProductModel PM
ON PMPD.ProductModelID = PM.ProductModelID
INNER JOIN AdventureWorks2017.Production.Product P
ON PM.ProductModelID = P.ProductModelID
 ) AS temp;

 Select *
 from #PMPDC;

 -- to check whether each product has transitions for all languages available.
 
 select cultureID, cultureName, count(distinct productID) as countOfProducts
 from #PMPDC
 group by CultureID, CultureName
 order by 1 desc;

 -- select all translations for a particular culture.

 -- tried to fully automate the process so that when the values in the table #PMPDC gets updated or deleted then variables also act accordingly in a dynamic way.

 declare @cultureList table (
    id int NOT NULL identity PRIMARY KEY,      -- declaring a table variable to store cultureID values
    cultureID varchar(40)
 );
 insert into @cultureList select distinct cultureID from #PMPDC;  -- inserting all culture ID Values into the table variable
  
 declare @listNum int;
 SELECT @listNum = COUNT(DISTINCT cultureID) from #PMPDC;  -- declaring variable to store the count of types of cultureID present

 declare @num int; 
 set @num = CEILING(RAND() * @listNum);  -- generating a random number in the range of count ( in this case 1-6 ) as there are 6 cultureID prersent

 declare @cultureVariable varchar(40);
 SELECT @cultureVariable = s.cultureID  -- Now with the help of randomly generated number selecting the cultureID 
 from @cultureList s
 where s.id = @num;

 SELECT *      -- Finally returning all records from #PMPDC belonging to the respective cultureID.
 FROM #PMPDC     
 WHERE CultureID = @cultureVariable;

 --------------------------------------------------------------------------------------------------------------------------------------------------------

 -- PRODUCT - PRODUCT_MODEL - PRODUCT_MODEL_ILLUSTRATION - ILLUSTRATION - LINE.

 -- getting the details of illustrations and diagrams used for product id's.

 SELECT ill.IllustrationID, ill.Diagram, pmill.ProductModelID, pm.Name as ModelName, 
 pm.CatalogDescription,pm.Instructions, p.ProductID, p.Name AS ProductName, p.ProductNumber
 FROM AdventureWorks2017.Production.Illustration ill
 inner join AdventureWorks2017.Production.ProductModelIllustration pmill
 on ill.IllustrationID = pmill.IllustrationID
 inner join AdventureWorks2017.Production.ProductModel pm
 on pmill.ProductModelID = pm.ProductModelID
 inner join AdventureWorks2017.Production.Product p
 on pm.ProductModelID = p.ProductModelID;

 -------------------------------------------------------------------------------------------------------------------------------------------------------

 --	BILL_OF_MATERIALS - UNIT_MEASURE - PRODUCT - LINE

 select *
 from AdventureWorks2017.Production.UnitMeasure;
 select *
 from AdventureWorks2017.Production.BillOfMaterials;
 select *
 from AdventureWorks2017.Production.Product;

 -- specific measurement.

 select p.Name as productName, SizeUnitMeasureCode as measureCode, u.Name as UnitMeasureName
 from AdventureWorks2017.Production.Product p
 join AdventureWorks2017.Production.UnitMeasure u
 on p.SizeUnitMeasureCode =u.UnitMeasureCode
 where SizeUnitMeasureCode is not null 
 UNION ALL
 select p.Name as productName, WeightUnitMeasureCode as MeasureCode, u.Name as UnitMeasureName
 from AdventureWorks2017.Production.Product p
 join AdventureWorks2017.Production.UnitMeasure u
 on p.WeightUnitMeasureCode =u.UnitMeasureCode
 where WeightUnitMeasureCode is not null 
 order by 3 asc

 -- both size and weight unit measure code together for the products in products table.

 WITH CTE AS (select *
 from AdventureWorks2017.Production.Product
 where SizeUnitMeasureCode is not null or WeightUnitMeasureCode is not null),

 CTE2 AS (select c.Name as productName, WeightUnitMeasureCode, u.Name as UnitMeasureName
 from CTE c
 join AdventureWorks2017.Production.UnitMeasure u
 on c.WeightUnitMeasureCode =u.UnitMeasureCode  
),

 CTE3 AS (select c.Name as productName, SizeUnitMeasureCode, u.Name as UnitMeasureName
 from CTE c
 left join AdventureWorks2017.Production.UnitMeasure u
 on c.SizeUnitMeasureCode =u.UnitMeasureCode  
 )
 SELECT a.productName, WeightUnitMeasureCode, a.UnitMeasureName, SizeUnitMeasureCode, b.UnitMeasureName
 from CTE2 a
 right join CTE3 b
 on a.productName = b.productName;

 -- query to select different or distinct set of values from two columns (Here billOfMaterials)

 /* SELECT DISTINCT LEAST(productAssemblyId, ComponentID) as ProductAssemblyID,
        GREATEST(productAssemblyID, ComponentID) as ComponentID
 from AdventureWorks2017.Production.BillOfMaterials */   
                   -- least and greatest functions are not supported in sql server. 

-- to find different number of components each assembly has and also how many components were ended from assembly

select productAssemblyID, count(distinct ComponentID) as noOfCompnonentsAtPresent, count(componentID) - count(distinct ComponentID) as endedAssemblyComponents
from AdventureWorks2017.Production.BillOfMaterials
where ProductAssemblyID is not null
group by ProductAssemblyID
order by 2 desc

-- to find total quantity for each parent productAssemblyID which are not ended.

WITH CTE AS (select *,
     CASE WHEN EndDate is not null then 1
	 else 0 end as Ended
from AdventureWorks2017.Production.BillOfMaterials
where ProductAssemblyID is not null
), 
CTE2 AS(
select ProductAssemblyID, P.Name as ProductName, sum(perAssemblyQty) as totalQty
from CTE 
inner join AdventureWorks2017.Production.Product p
on CTE.ProductAssemblyID = p.ProductID
where ended = 0
group by ProductAssemblyID, P.Name
),
CTE3 AS (
select b.ProductAssemblyID, ProductName, totalQty, EndedAssemblyQuantity
from (SELECT productAssemblyID, 
             sum(perAssemblyQty) as EndedAssemblyQuantity
      from CTE
      where ended = 1
      group by ProductAssemblyID) a
right join CTE2 b
on a.ProductAssemblyID = b.ProductAssemblyID
)
SELECT a.ProductAssemblyID,
       a.ProductName,
       a.totalQty,
       a.EndedAssemblyQuantity,
       b.BillOfMaterialsID,
       b.UnitMeasureCode,
       c.Name
FROM CTE3 A
join AdventureWorks2017.Production.BillOfMaterials b
on a.ProductAssemblyID = b.ProductAssemblyID
join AdventureWorks2017.Production.UnitMeasure c
on b.UnitMeasureCode = c.UnitMeasureCode;

-------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- PRODUCT - PRODUCT_DOCUMENT - DOCUMENT - LINE (AND) PRODUCT - PRODUCT_PRODUCT_PHOTO - PRODUCT_PHOTO - LINE
-- these lines are just used for documentation purposes to store the information related to respective photos that a product uses 
-- and documents related to those product. (These lines do not have to be analysed).

------------------------------------------------------------------------------------------------------------------------------------------------------------------

--------------------------  END -------------------------- OF --------------------------- THE ------------------------------- PROJECT ---------------------------- 

