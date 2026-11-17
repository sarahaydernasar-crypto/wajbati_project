"""Cafeteria reports use delivery time for all sales metrics."""

from datetime import date, datetime, time, timedelta

from fastapi import HTTPException
from sqlalchemy import func, select

from . import logic
from .models import DELIVERED, Order, OrderLine


def report(db, cafeteria_id: int, period: str, start_date: date | None, end_date: date | None) -> dict:
    today = logic.now().date()
    if period == "today":
        first = last = today
    elif period == "week":
        first, last = today - timedelta(days=6), today
    elif period == "month":
        first, last = today.replace(day=1), today
    else:
        if start_date is None or end_date is None:
            raise HTTPException(422, "اختر تاريخ البداية والنهاية")
        first, last = start_date, end_date
    if first > last or (last - first).days >= 366:
        raise HTTPException(422, "اختر فترة صحيحة لا تتجاوز 366 يوماً")

    start = datetime.combine(first, time.min)
    end = datetime.combine(last, time.min) + timedelta(days=1)
    # Only historical records without a delivery timestamp use their creation date.
    delivered_time = func.coalesce(Order.delivered_at, Order.created_at)
    conditions = (Order.cafeteria_id == cafeteria_id, Order.status == DELIVERED,
                  delivered_time >= start, delivered_time < end)
    sales, count = db.execute(select(func.coalesce(func.sum(Order.total), 0), func.count())
                              .where(*conditions)).one()
    estimated = db.scalar(select(func.count()).select_from(Order)
                          .where(*conditions, Order.delivered_at.is_(None)))
    created_count = db.scalar(select(func.count()).select_from(Order).where(
        Order.cafeteria_id == cafeteria_id, Order.created_at >= start, Order.created_at < end))
    top = db.execute(select(OrderLine.item_name, func.sum(OrderLine.quantity),
                            func.sum(OrderLine.quantity * OrderLine.unit_price))
                     .join(Order, Order.id == OrderLine.order_id).where(*conditions)
                     .group_by(OrderLine.item_name)
                     .order_by(func.sum(OrderLine.quantity).desc(), OrderLine.item_name).limit(5)).all()
    day = func.date(delivered_time)
    rows = db.execute(select(day, func.sum(Order.total), func.count()).where(*conditions)
                      .group_by(day).order_by(day)).all()
    by_day = {str(d): (int(total), int(number)) for d, total, number in rows}
    series = []
    cursor = first
    while cursor <= last:
        key = cursor.isoformat()
        total, number = by_day.get(key, (0, 0))
        series.append({"date": key, "sales": total, "orders": number})
        cursor += timedelta(days=1)
    return {"period": period, "start_date": first.isoformat(), "end_date": last.isoformat(),
            "timezone": str(logic.TIMEZONE), "sales": int(sales), "delivered_orders": int(count),
            "created_orders": int(created_count), "average_order_value": round(sales / count) if count else 0,
            "estimated_orders": int(estimated), "series": series,
            "top_items": [{"name": name, "quantity": int(quantity), "sales": int(total)}
                          for name, quantity, total in top]}
