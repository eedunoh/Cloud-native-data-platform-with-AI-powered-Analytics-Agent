SELECT *
FROM {{ref("streamed_sales")}}
WHERE delivery_date < order_date