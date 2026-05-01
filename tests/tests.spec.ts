// Used AI assisted programming
// Partly generated using GitHub Copilot and corrected by me

import { afterAll, describe, expect, test } from "bun:test";

describe("food order system", async () => {
  let authToken: string = "";
  afterAll(async () => {
    await fetch("http://localhost:8080/auth/user", {
      method: "DELETE",
      headers: {
        Authorization: `Bearer ${authToken}`,
      },
    });
  });

  describe("menu service", () => {
    let createdId: string = "";

    test("healthcheck", async () => {
      await fetch("http://localhost:8080/menu/healthcheck");
    });

    test("create item", async () => {
      const body = {
        name: "Tomato",
        price: 1.23,
        description: "It's a fruit",
        ingredients: ["Natural Sugar", "Sunlight"],
      };

      const result = await fetch("http://localhost:8080/menu", {
        method: "POST",
        body: JSON.stringify(body),
      });

      expect(result.status).toBe(201);

      const json: any = await result.json();
      expect(json).toContainKey("id");
      expect(json["id"].length).toBe(24);

      createdId = json["id"];
    });

    test("get item", async () => {
      const expected = {
        name: "Tomato",
        price: 1.23,
        description: "It's a fruit",
        ingredients: ["Natural Sugar", "Sunlight"],
      };

      const result = await fetch(`http://localhost:8080/menu/${createdId}`);

      let json = await result.json();
      expect(json).toContainKeys(Object.keys(expected));
      expect(json).toContainValues([
        "Tomato",
        "It's a fruit",
        ["Natural Sugar", "Sunlight"],
      ]);
    });

    test("get all items", async () => {
      const result = await fetch("http://localhost:8080/menu");
      const json = (await result.json()) as Object[];

      expect(json).toBeArray();
      expect(json.length).toBeGreaterThan(0);
    });

    test("update item", async () => {
      const body = {
        name: "Grape Tomato",
        price: 2000.23,
        description: "No it's a vegetable",
        ingredients: ["Natural Sugar", "Sunlight", "Inflation"],
      };

      const result = await fetch(`http://localhost:8080/menu/${createdId}`, {
        method: "PUT",
        body: JSON.stringify(body),
      });

      expect(result.status).toBe(200);
    });

    test("delete item", async () => {
      const result = await fetch(`http://localhost:8080/menu/${createdId}`, {
        method: "DELETE",
      });

      expect(result.status).toBe(200);
    });
  });

  describe("authentication service", () => {
    test("healthcheck", async () => {
      await fetch("http://localhost:8080/auth/healthcheck");
    });

    test("register", async () => {
      const body = {
        username: "testuser",
        password: btoa("strong_password"),
        firstName: "hello",
        lastName: "world",
      };

      const result = await fetch("http://localhost:8080/auth/register", {
        method: "POST",
        body: JSON.stringify(body),
      });
      expect(result.status).toBe(200);

      const token = ((await result.json()) as { token: string }).token;
      const isJwtFormat = /^.+\..+\..+$/.test(token);
      expect(isJwtFormat).toBeTrue();

      authToken = token;
    });

    test("login", async () => {
      const body = {
        username: "testuser",
        password: btoa("strong_password"),
      };

      const result = await fetch("http://localhost:8080/auth/login", {
        method: "POST",
        body: JSON.stringify(body),
      });
      expect(result.status).toBe(200);

      const token = ((await result.json()) as { token: string }).token;
      const isJwtFormat = /^.+\..+\..+$/.test(token);
      expect(isJwtFormat).toBeTrue();

      authToken = token;
    });

    test("delete user", async () => {
      const body = {
        username: "deleteduser",
        password: btoa("weak_password"),
      };

      const result = await fetch("http://localhost:8080/auth/register", {
        method: "POST",
        body: JSON.stringify(body),
      });
      expect(result.status).toBe(200);

      const token = ((await result.json()) as { token: string }).token;

      const deleteResult = await fetch("http://localhost:8080/auth/user", {
        method: "DELETE",
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });
      expect(deleteResult.status).toBe(200);
    });

    test("get user", async () => {
      const expectation = {
        username: "testuser",
        first_name: "hello",
        last_name: "world",
        admin: false,
      };

      const result = await fetch("http://localhost:8080/auth/user", {
        headers: {
          Authorization: `Bearer ${authToken}`,
        },
      });
      expect(result.status).toBe(200);

      const user = ((await result.json()) as any).users;
      expect(user).toContainAllKeys(Object.keys(expectation));
      expect(user).toContainAllValues(Object.values(expectation));
    });
  });

  describe("basket service", () => {
    test("healthcheck", async () => {
      await fetch("http://localhost:8080/basket/healthcheck");
    });

    test("insert item", async () => {
      const body = {
        foodName: "Tomato",
        price: 1.23,
        quantity: 3,
      };

      const result = await fetch("http://localhost:8080/basket/order/1", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authToken}`,
        },
        body: JSON.stringify(body),
      });
      expect(result.status).toBe(201);
    });

    test("get all items", async () => {
      const result = await fetch("http://localhost:8080/basket/order-list", {
        headers: {
          Authorization: `Bearer ${authToken}`,
        },
      });
      expect(result.status).toBe(200);

      const json = (await result.json()) as Object[];
      expect(json).toBeArray();
      expect(json).not.toBeEmpty();
    });

    test("update item", async () => {
      const body = {
        foodName: "Tomato",
        quantity: 3,
      };

      const result = await fetch("http://localhost:8080/basket/order/1", {
        method: "PATCH",
        headers: {
          Authorization: `Bearer ${authToken}`,
        },
        body: JSON.stringify(body),
      });
      expect(result.status).toBe(200);
    });

    test("delete item", async () => {
      const body = { foodName: "Tomato" };

      const result = await fetch("http://localhost:8080/basket/order/1", {
        method: "DELETE",
        headers: {
          Authorization: `Bearer ${authToken}`,
        },
        body: JSON.stringify(body),
      });
      expect(result.status).toBe(200);
    });

    test("deleted all items", async () => {
      const result = await fetch("http://localhost:8080/basket/order-list", {
        headers: {
          Authorization: `Bearer ${authToken}`,
        },
      });
      expect(result.status).toBe(200);

      const json = (await result.json()) as Object[];
      expect(json).toBeArray();
      expect(json.length).toBeEmpty();
    });

    test("submit items for order", async () => {
      const body = {
        foodName: "Tomato",
        price: 1.23,
        quantity: 3,
      };

      const result = await fetch("http://localhost:8080/basket/order/1", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authToken}`,
        },
        body: JSON.stringify(body),
      });
      expect(result.status).toBe(201);

      const submitResult = await fetch(
        "http://localhost:8080/basket/submit-items",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${authToken}`,
          },
        },
      );
      expect(submitResult.status).toBe(202);
    });
  });

  describe("order manager service", () => {
    let createdOrderId: number | undefined = undefined;

    test("healthcheck", async () => {
      await fetch("http://localhost:8080/man/healthcheck");
    });

    test("create order", async () => {
      const result = await fetch("http://localhost:8080/man/order", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authToken}`,
        },
      });
      expect(result.status).toBe(200);

      const orderId = ((await result.json()) as { orderId: number }).orderId;
      expect(orderId).toBeDefined();

      createdOrderId = orderId;
    });

    test("get orders", async () => {
      const result = await fetch("http://localhost:8080/man/orders", {
        headers: {
          Authorization: `Bearer ${authToken}`,
        },
      });
      expect(result.status).toBe(200);

      const orders = ((await result.json()) as any).order;
      expect(orders).toBeArray();
      expect(orders).not.toBeEmpty();
    });

    test("update order", async () => {
      const body = { status: "completed" };
      const result = await fetch(
        `http://localhost:8080/man/order/${createdOrderId}`,
        {
          method: "PUT",
          headers: {
            Authorization: `Bearer ${authToken}`,
          },
          body: JSON.stringify(body),
        },
      );
      expect(result.status).toBe(200);
    });

    test("delete orders", async () => {
      const result = await fetch("http://localhost:8080/man/orders", {
        headers: {
          Authorization: `Bearer ${authToken}`,
        },
      });
      const orders = ((await result.json()) as any).order;

      orders.forEach(async (order: any) => {
        const deleteResult = await fetch(
          `http://localhost:8080/man/order/${order.order_id}`,
          {
            method: "DELETE",
            headers: {
              Authorization: `Bearer ${authToken}`,
            },
          },
        );
        expect(deleteResult.status).toBe(200);
      });
    });
  });
});
