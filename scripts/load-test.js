// k6 load test to demonstrate ECS autoscaling.
//   docker run --rm -i -e BASE_URL=https://dxxxx.cloudfront.net grafana/k6 run - < scripts/load-test.js
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "1m", target: 20 },
    { duration: "5m", target: 60 },
    { duration: "1m", target: 0 },
  ],
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<800"],
  },
};

const BASE = __ENV.BASE_URL;

export default function () {
  const r = http.get(`${BASE}/api/messages?limit=50`);
  check(r, { "status 200": (res) => res.status === 200 });
  if (__ITER % 10 === 0) {
    http.post(`${BASE}/api/messages`, JSON.stringify({ author: "k6", body: `load ${__VU}-${__ITER}` }), {
      headers: { "Content-Type": "application/json" },
    });
  }
  sleep(0.2);
}
