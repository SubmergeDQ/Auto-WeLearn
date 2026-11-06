import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * 本地 mock 平台。用 node:http 手写，不引 nock —— 减少依赖，也让「请求体逐字段断言」
 * 变成对真实 HTTP 流量的断言，而不是对拦截器参数的断言。
 */

export interface RecordedRequest {
  method: string;
  pathname: string;
  query: URLSearchParams;
  body: string;
  headers: IncomingMessage['headers'];
}

export interface MockServer {
  baseUrl: string;
  requests: RecordedRequest[];
  /** 这些 action 返回 ret=1，用于模拟平台拒绝 */
  failActions: Set<string>;
  /** 取出所有 SCO 写操作 action，用于断言 dry-run 零写入 */
  writeActions(): string[];
  /** 按 action 取出请求体参数列表 */
  calls(action: string): URLSearchParams[];
  close(): Promise<void>;
}

const COURSE_INFO_HTML = `<!DOCTYPE html><html><body>
<script>var course = {"uid":123,"classid":"abc","cid":1};</script>
</body></html>`;

const LOGIN_WALL = `<script type='text/javascript'>if(this==top) location.href='/user/prelogin.aspx?loginret=x';</script>`;

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (chunk) => {
      data += String(chunk);
    });
    req.on('end', () => resolve(data));
  });
}

function json(res: ServerResponse, payload: unknown): void {
  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

function html(res: ServerResponse, body: string): void {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(body);
}

export async function startMockServer(): Promise<MockServer> {
  const requests: RecordedRequest[] = [];
  const failActions = new Set<string>();
  const fixture = readFileSync(join(process.cwd(), 'fixtures', 'sco-courseware.html'), 'utf8');

  const server = createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', 'http://127.0.0.1');
    const body = await readBody(req);
    const record: RecordedRequest = {
      method: req.method ?? 'GET',
      pathname: url.pathname,
      query: url.searchParams,
      body,
      headers: req.headers,
    };
    requests.push(record);

    const cookie = req.headers.cookie ?? '';

    if (url.pathname === '/ajax/authCourse.aspx') {
      if (!cookie || cookie.includes('expired')) {
        html(res, LOGIN_WALL);
        return;
      }
      json(res, { ret: 0, clist: [{ cid: 900, name: 'Mock Course', per: 40 }] });
      return;
    }

    if (url.pathname === '/student/course_info.aspx') {
      html(res, COURSE_INFO_HTML);
      return;
    }

    if (url.pathname === '/ajax/StudyStat.aspx') {
      const action = url.searchParams.get('action');
      if (action === 'courseunits') {
        json(res, {
          ret: 0,
          info: [
            { unitname: 'Unit 01', name: 'Unit 1', visible: 'true' },
            { unitname: 'Unit 02', name: 'Unit 2', visible: 'true' },
          ],
        });
        return;
      }
      if (action === 'scoLeaves') {
        const unitidx = url.searchParams.get('unitidx');
        if (unitidx === '0') {
          json(res, {
            ret: 0,
            info: [
              { id: 'sco-done', location: 'Unit 1 > Finished', iscomplete: '已完成', isvisible: 'true', crate: '100', learntime: '00:01:00' },
              { id: 'sco-todo', location: 'Unit 1 > Task 1', iscomplete: '未完成', isvisible: 'true', crate: '-', learntime: '00:00:00' },
              { id: 'sco-hidden', location: 'Unit 1 > Hidden', iscomplete: '未完成', isvisible: 'false', crate: '-', learntime: '00:00:00' },
            ],
          });
          return;
        }
        if (unitidx === '1') {
          json(res, {
            ret: 0,
            info: [
              { id: 'sco-oral', location: 'Unit 2 > Oral Practice', iscomplete: '未完成', isvisible: 'true', crate: '-', learntime: '00:00:00' },
            ],
          });
          return;
        }
        if (unitidx === '99') {
          html(res, '出错了');
          return;
        }
        json(res, { ret: 0, info: [] });
        return;
      }
      html(res, '出错了');
      return;
    }

    if (url.pathname === '/Ajax/SCO.aspx') {
      const params = new URLSearchParams(body);
      const action = params.get('action') ?? '';

      if (action === 'scoAddr') {
        json(res, {
          ret: 0,
          addr: `//127.0.0.1:${(server.address() as { port: number }).port}/courseware/main1.html?${params.get(
            'scoid',
          )}|Unit 1 > Task 1`,
        });
        return;
      }

      if (failActions.has(action)) {
        json(res, { ret: 1, mess: 'rejected' });
        return;
      }

      if (action === 'getscoinfo_v7') {
        // 从未提交过的小节平台返回 -1，用于验证「无历史 CMI」分支
        if ((params.get('scoid') ?? '').startsWith('sco-fresh')) {
          json(res, { ret: -1, msg: '学习数据不正确' });
          return;
        }
        json(res, {
          ret: 0,
          comment: JSON.stringify({ cmi: { total_time: '120', session_time: '0', completion_status: 'not_attempted' } }),
        });
        return;
      }

      json(res, { ret: 0 });
      return;
    }

    if (url.pathname === '/courseware/main1.html') {
      // sco-empty* 用来模拟「纯媒体页」：合法页面但没有任何题目
      const scoid = url.searchParams.keys().next().value ?? '';
      html(res, String(scoid).startsWith('sco-empty') ? '<html><body><p>media only</p></body></html>' : fixture);
      return;
    }

    res.writeHead(404);
    res.end('not found');
  });

  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = (server.address() as { port: number }).port;

  return {
    baseUrl: `http://127.0.0.1:${port}`,
    requests,
    failActions,
    writeActions: () =>
      requests
        .filter((r) => r.pathname === '/Ajax/SCO.aspx')
        .map((r) => new URLSearchParams(r.body).get('action') ?? '')
        .filter((a) => a.length > 0 && a !== 'scoAddr'),
    calls: (action) =>
      requests
        .filter((r) => r.pathname === '/Ajax/SCO.aspx')
        .map((r) => new URLSearchParams(r.body))
        .filter((p) => p.get('action') === action),
    close: () =>
      new Promise<void>((resolve, reject) => {
        server.close((err) => (err ? reject(err) : resolve()));
      }),
  };
}
