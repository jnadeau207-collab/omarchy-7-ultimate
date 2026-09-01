"""Durable bounded event publication and live subscription fan-out."""

from __future__ import annotations

import asyncio
import uuid
from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from .db import FabricDatabase
from .models import DEFAULT_EVENT_RETENTION, MAX_SUBSCRIBER_BACKLOG

@dataclass
class EventSubscription:
    subscription_id: str
    topics: tuple[str, ...]
    queue: asyncio.Queue[dict[str, Any]]
    active: bool = True

    def matches(self, topic: str) -> bool:
        return "*" in self.topics or topic in self.topics

class EventBroker:
    def __init__(
        self,
        database: FabricDatabase,
        *,
        retention: int = DEFAULT_EVENT_RETENTION,
        subscriber_backlog: int = MAX_SUBSCRIBER_BACKLOG,
    ) -> None:
        if retention < 1:
            raise ValueError("event retention must be positive")
        if subscriber_backlog < 1:
            raise ValueError("subscriber backlog must be positive")
        self.database = database
        self.retention = retention
        self.subscriber_backlog = subscriber_backlog
        self._subscriptions: dict[str, EventSubscription] = {}

    @property
    def subscription_count(self) -> int:
        return len(self._subscriptions)

    def subscribe(self, topics: Sequence[str]) -> EventSubscription:
        subscription = EventSubscription(
            subscription_id=str(uuid.uuid4()),
            topics=tuple(topics),
            queue=asyncio.Queue(maxsize=self.subscriber_backlog),
        )
        self._subscriptions[subscription.subscription_id] = subscription
        return subscription

    def unsubscribe(self, subscription_id: str) -> bool:
        subscription = self._subscriptions.pop(subscription_id, None)
        if subscription is None:
            return False
        subscription.active = False
        return True

    def publish(self, topic: str, payload: Mapping[str, Any]) -> dict[str, Any]:
        event = self.database.append_event(topic, payload, retention=self.retention)
        self.deliver(event)
        return event

    def deliver(self, event: dict[str, Any]) -> None:
        topic = event["topic"]
        for subscription in list(self._subscriptions.values()):
            if not subscription.active or not subscription.matches(topic):
                continue
            try:
                subscription.queue.put_nowait(event)
            except asyncio.QueueFull:
                while True:
                    try:
                        subscription.queue.get_nowait()
                    except asyncio.QueueEmpty:
                        break
                subscription.active = False
                subscription.queue.put_nowait(
                    {
                        "sequence": event["sequence"],
                        "id": str(uuid.uuid4()),
                        "topic": "fabric.subscription-overflow",
                        "payload": {
                            "subscriptionId": subscription.subscription_id,
                            "recoveryAction": "events.reconnect-and-replay",
                        },
                        "createdAt": event["createdAt"],
                    }
                )
                self._subscriptions.pop(subscription.subscription_id, None)

    def close(self) -> None:
        for subscription in self._subscriptions.values():
            subscription.active = False
        self._subscriptions.clear()
