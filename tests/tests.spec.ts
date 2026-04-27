import { describe, expect, test } from "bun:test";

describe("menu service", () => {
  test("healthcheck", async () => {
    fetch("http://localhost:8080/menu/healthcheck").catch(() =>
      expect().fail(),
    );
  });
});

describe("basket service", () => {
  test("healthcheck", async () => {
    fetch("http://localhost:8080/basket/healthcheck").catch(() =>
      expect().fail(),
    );
  });
});

describe("authentication service", () => {
  test("healthcheck", async () => {
    fetch("http://localhost:8080/auth/healthcheck").catch(() =>
      expect().fail(),
    );
  });
});

describe("order manager service", () => {
  test("healthcheck", async () => {
    fetch("http://localhost:8080/man/healthcheck").catch(() => expect().fail());
  });
});
