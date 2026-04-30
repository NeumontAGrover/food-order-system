import { describe, expect, test } from "bun:test";

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
    // Genereated from GitHub Copilot
    const result = await fetch(`http://localhost:8080/menu/${createdId}`, {
      method: "DELETE",
    });

    expect(result.status).toBe(200);
  });
});

describe("basket service", () => {
  test("healthcheck", async () => {
    await fetch("http://localhost:8080/basket/healthcheck");
  });
});

describe("authentication service", () => {
  test("healthcheck", async () => {
    await fetch("http://localhost:8080/auth/healthcheck");
  });
});

describe("order manager service", () => {
  test("healthcheck", async () => {
    await fetch("http://localhost:8080/man/healthcheck");
  });
});
