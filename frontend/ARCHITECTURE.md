# Kiến trúc Module: Frontend

**Branch:** `feat/frontend`  
**Mục đích:** Next.js 14+ App Router TypeScript — UI dashboard quản lý server, giám sát real-time, deployment, alerting, và web terminal.

---

## Cấu trúc App Router

```
frontend/app/
├── (auth)/
│   ├── login/page.tsx         # Form đăng nhập, OAuth2 buttons
│   └── register/page.tsx      # Form đăng ký
│
├── dashboard/
│   ├── layout.tsx             # Sidebar navigation, auth guard
│   ├── page.tsx               # Overview: server count, alerts, recent deploys
│   │
│   ├── servers/
│   │   ├── page.tsx           # Danh sách servers, status badges
│   │   └── [id]/
│   │       ├── page.tsx       # Server detail, hardware info
│   │       ├── metrics/page.tsx    # Real-time charts CPU/RAM/Disk/Network
│   │       ├── terminal/page.tsx   # Xterm.js SSH terminal
│   │       └── deployments/page.tsx # Deployment history + trigger
│   │
│   ├── credentials/page.tsx   # CRUD credentials (không show raw key)
│   ├── alerts/page.tsx        # Alert rules + recent events
│   └── settings/page.tsx      # User profile, 2FA setup
│
└── api/                       # Route Handlers (BFF — không expose trực tiếp)
    ├── auth/[...nextauth]/route.ts
    └── proxy/[...path]/route.ts  # Forward request đến backend
```

## Thư viện chính

| Thư viện | Mục đích |
|---|---|
| `@tanstack/react-query` | Server state, cache, refetch |
| `recharts` | LineChart real-time metrics |
| `@xterm/xterm` | Terminal emulator |
| `@xterm/addon-fit` | Auto-fit terminal kích thước |
| `zustand` | Client state (auth, UI) |
| `zod` | Form validation schemas |
| `lucide-react` | Icon library |

## Data Fetching Pattern

```tsx
// Server Components (SSR): dữ liệu khởi đầu không nhạy cảm
// Client Components: real-time qua React Query + WebSocket

// Ví dụ: Server List
export default async function ServersPage() {
  const servers = await fetchServers()  // Server-side fetch
  return <ServerList initialData={servers} />  // Hydrate client
}

// Client component nhận initial data, refetch mỗi 30 giây
function ServerList({ initialData }) {
  const { data } = useQuery({
    queryKey: ['servers'],
    queryFn: fetchServers,
    initialData,
    refetchInterval: 30_000,
  })
}
```

## WebSocket Hooks

```tsx
// useMetricsWS.ts — nhận metrics real-time
function useMetricsWS(serverID: string) {
  const [metrics, setMetrics] = useState<MetricsPoint[]>([])
  // WebSocket → parse JSON → setMetrics
  // Return: metrics (array 60 points), status (connected/disconnected)
}

// useTerminalWS.ts — SSH terminal session
function useTerminalWS(serverID: string, term: Terminal) {
  // WebSocket binary → term.write()
  // term.onData → ws.send()
}
```

## Bảo mật Frontend

- JWT lưu trong `httpOnly` cookie (không localStorage)
- Tất cả API calls qua BFF route handler — không gọi backend trực tiếp từ browser
- CSP headers trong `next.config.js`

## Task Liên quan: P6 (charts), P9 (terminal)
