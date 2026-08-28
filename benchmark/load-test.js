import http from 'k6/http';
import { check, sleep, group } from 'k6';

export const options = {
  stages: [
    { duration: '10s', target: 100 },
    { duration: '10s', target: 200 },
    { duration: '30s', target: 200 },
    { duration: '10s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<300', 'p(99)<800'],
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
  },
};

export default function () {
  const baseUrl = 'http://localhost:8080';
  const headers = { 'Content-Type': 'application/json' };
  const rnd = Math.random();

  if (rnd < 0.4) {
    // 40% GET /api/transactions?accountNumber=ACC-xxx&limit=20 (account-scoped, indexed)
    group('GET list - 40%', function () {
      const res = http.get(`${baseUrl}/api/transactions?accountNumber=ACC-${Math.floor(Math.random()*50)+1}&limit=20`);
      check(res, {
        'GET list status is 200': (r) => r.status === 200,
      });
    });
  } else if (rnd < 0.7) {
    // 30% GET /api/transactions/{id 1-100}: IDs 1..100 are always present in seed 1..1000
    group('GET single - 30%', function () {
      const id = Math.floor(Math.random() * 100) + 1;
      const res = http.get(`${baseUrl}/api/transactions/${id}`);
      check(res, {
        'GET single status is 200': (r) => r.status === 200,
      });
    });
  } else if (rnd < 0.9) {
    // 20% POST /api/transactions with JSON -> expect 201
    group('POST create - 20%', function () {
      const payload = JSON.stringify({
        accountNumber: 'ACC-' + Math.floor(Math.random() * 100000),
        amount: parseFloat((Math.random() * 10000).toFixed(4)),
        description: 'bench-' + Math.random().toString(36).substring(2, 10),
      });
      const res = http.post(`${baseUrl}/api/transactions`, payload, { headers });
      check(res, {
        'POST status is 201': (r) => r.status === 201,
      });
    });
  } else {
    // 10% PUT /api/transactions/{id 1-100}
    group('PUT update - 10%', function () {
      const id = Math.floor(Math.random() * 100) + 1;
      const payload = JSON.stringify({
        accountNumber: 'ACC-' + Math.floor(Math.random() * 100000),
        amount: parseFloat((Math.random() * 10000).toFixed(4)),
        description: 'bench-' + Math.random().toString(36).substring(2, 10),
      });
      const res = http.put(`${baseUrl}/api/transactions/${id}`, payload, { headers });
      check(res, {
        'PUT status is 200': (r) => r.status === 200,
      });
    });
  }

  sleep(0.1);
}
