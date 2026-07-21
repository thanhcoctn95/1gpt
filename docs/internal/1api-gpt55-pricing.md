# [NỘI BỘ] Bảng giá 1GPT / 1API cho GPT-5.5

> **Tài liệu nội bộ — không public.** Không hiển thị hoặc nhắc tên nhà cung cấp upstream trên portal, landing page, dashboard, bảng giá công khai hay nội dung sales public. Khi cần mô tả nguồn model, chỉ dùng các cụm như **hạ tầng API**, **nguồn model đối tác**, hoặc **managed API layer**.

> **Public branding rule:** mọi bề mặt người dùng của 1API (`src/potal/frontend`, `new_ui`, landing page, public dashboard/API response, screenshot/sales material) chỉ được hiển thị **token**, **internal cost**, hoặc **nguồn model**. Không đưa tên vendor/upstream, URL vendor, account pool, hay provider-specific quota/cost unit ra ngoài. Tên nhà cung cấp chỉ được phép nằm trong docs nội bộ như file này hoặc artifact vận hành không public.

Tài liệu này là source of truth nội bộ cho bảng giá **1GPT / 1API GPT-5.5 API** dùng cho code, coding agent, automation và team nhỏ.

## Nguyên tắc chuẩn hoá

- **Token user-facing:** số dư và usage hiển thị theo token/quota đã tính phí. Không dùng lớp quy đổi riêng trên portal.
- **User quota:** trừ theo OpenAI-style input/output weighting để tối đa hoá lợi nhuận: `gpt-5.5`, `gpt-5.5-xhigh`, `opus-4.8`, `opus-4.8-thinking`, `claude-opus-4.8`, `claude-opus-4.8-thinking` input `1.5x`/output `6x` (đổi từ `1.2x` ngày 2026-07-12); `gpt-5.4` input `0.5x`/output `3x`; GLM giữ rate tiết kiệm hiện tại.
- **Source/VietAPI cost:** chỉ dùng nội bộ để tính margin/profit; không quyết định trực tiếp số dư user bị trừ và không hiển thị public.
- **Gói tháng:** token quota reset hằng ngày, không cộng dồn.
- **Gói one-time:** mua một lần, dùng đến khi hết, không reset, không hết hạn trong thực tế vận hành.
- **Giá hiển thị:** VND.
- **Public UI/code:** không nhắc tên nhà cung cấp nguồn, upstream/vendor URL, account pool, hay provider-specific quota/cost unit.

---

## Đơn vị hiển thị: CREDIT (cập nhật 2026-07-09)

Từ 2026-07-09, mọi bề mặt user/admin của portal hiển thị chi phí theo **credit** thay cho "token". Đây là lớp hiển thị suy ra trực tiếp từ quota nội bộ, **không** thay đổi engine metering của New API.

### Định nghĩa

```text
1 credit = 1.000.000 quota units nội bộ
```

Quota units là đơn vị New API thực trừ (ghi vào `logs.quota` và `user_subscriptions.amount_*`). Vì `gpt-5.5` input có ratio `1.0` (1 token input = 1 quota unit), 1 credit tương đương chi phí của **1M token input gpt-5.5** — khớp cách gọi "1.0 cr/1M token" trên web pricing.

### Quy đổi

- Số dư / usage hiển thị: `credit = quota / 1.000.000`. Ví dụ gói `20.000.000` quota → `20 credit`.
- Credit/1M token của mỗi model = `model_ratio` (input) và `model_ratio × completion_ratio` (output). Bảng tham chiếu web pricing:

| Nhóm | Model | credit / 1M token |
| --- | --- | ---: |
| Rẻ | `deepseek-v4-flash` | `0.1` |
| Rẻ | `glm-5.1`, `kimi-k2.6` | `0.25` |
| Rẻ | `deepseek-v4-pro`, `glm-5.2`, `kimi-2.7`, `grok-4.5` | `0.5` |
| Rẻ | `grok-4.3` | `0.6` |
| TOP | `gpt-5.5`, `gpt-5.5-high`, `gpt-5.5-xhigh` | `1.0` |
| TOP | `gpt-5.6-sol` | `2.0` |
| TOP | `gpt-5.6-terra` | `1.5` |
| TOP | `claude-sonnet-5` | `0.5` |
| TOP | `claude-opus-4.6/4.7/4.8` (+thinking), KIRO | `1.0` |

### Lưu ý về input/output weighting

Bảng credit/1M ở trên là **rate tham chiếu (chuẩn theo input)**. Các model premium (`gpt-5.5`, `opus-4.8`) hiện vẫn trừ output nặng hơn input (`p * 1.5 + c * 6` ở tầng `billing_expr`), nên credit output thực tế cao hơn credit input. Việc "phẳng hoá" output về đúng 1.0 cr/1M cho cả input lẫn output là **thay đổi doanh thu lớn** và chỉ áp dụng qua migration riêng khi được duyệt (xem `src/deploy/migration-2026-07-09-credit-billing-flatten.sql`).

`gpt-5.6-sol` (2 cr/1M input) và `gpt-5.6-terra` (1.5 cr/1M input) dùng cùng cơ chế: input là rate tham chiếu, output vẫn trừ nặng như `gpt-5.5` (6 cr/1M output, tức `c * 12` ở `billing_expr`). Rate ban đầu nằm trong `src/deploy/migration-2026-07-10-gpt56-sol-terra.sql`; mức hiện tại được cập nhật bởi `src/deploy/migration-2026-07-21-gpt56-sol-terra-input-rates.sql`.

### Migrate số dư

Không cần migrate dữ liệu: credit là lớp hiển thị `quota / 1.000.000`. Số dư quota hiện tại của user giữ nguyên, chỉ đổi cách hiển thị và cách admin nhập khi "Cấp thêm" (nhập theo credit, backend nhân `1.000.000` để ra quota units).

### Files liên quan (credit)

- `src/potal/frontend/src/lib/format.ts` — `QUOTA_PER_CREDIT`, `quotaToCredit`, `formatCredit`, `formatCreditRate`.
- `src/potal/frontend/src/views/**` + `src/potal/frontend/src/i18n/locales/{en,vi}.ts` — nhãn credit.
- `src/potal/backend/.../ProvisioningController.java`, `PricingController.java` — mô tả gói theo credit.

---

## 0. Flow quota/token và internal upstream cost

### Quyết định vận hành

1API tách rõ hai lớp tính toán:

| Lớp           | Mục đích                             | Công thức                                     | Dùng để                                       |
| ------------- | ------------------------------------ | --------------------------------------------- | --------------------------------------------- |
| User quota    | Số dư khách hàng nhìn thấy và bị trừ | OpenAI-style price weighting                  | Subscription, token pack, dashboard usage     |
| Internal cost | Đối soát chi phí nguồn model nội bộ  | Theo chi phí thực tế 1API trả cho nguồn model | Profit/margin, cảnh báo cost, vận hành nội bộ |

Chính sách mới: **tối đa hóa lợi nhuận bằng cách tính user theo bảng giá OpenAI API**, còn chi phí 1API trả cho nguồn model chỉ dùng để tính margin nội bộ.

Không công khai tên nhà cung cấp, URL nhà cung cấp, account pool hoặc provider-specific quota/cost units trên các bề mặt user-facing.

### Baseline billed token

Baseline user-facing:

```text
1 billed token/quota unit = đơn vị tính phí user-facing sau khi áp input/output multiplier
```

Theo OpenAI API pricing đã kiểm tra ngày 2026-06-28:

| Model                 | OpenAI-style input / 1M | OpenAI-style cached input / 1M | OpenAI-style output / 1M | User quota rule   |
| --------------------- | ----------------------: | -----------------------------: | -----------------------: | ----------------- |
| `gpt-5.5`             |                 `$5.00` |                        `$0.50` |                 `$30.00` | `p * 1.5 + c * 6` |
| `gpt-5.5-xhigh`       |                 `$5.00` |                        `$0.50` |                 `$30.00` | `p * 1.5 + c * 6` |
| `opus-4.8-thinking`   |                 `$5.00` |                        `$0.50` |                 `$30.00` | `p * 1.5 + c * 6` |
| `gpt-5.4`             |                 `$2.50` |                        `$0.25` |                 `$15.00` | `p * 0.5 + c * 3` |

User quota examples:

```text
gpt-5.5 / gpt-5.5-xhigh
prompt_tokens=1000, completion_tokens=500
user_quota = 1000 * 1.5 + 500 * 6 = 4500 billed token

opus-4.8-thinking
prompt_tokens=1000, completion_tokens=500
user_quota = 1000 * 1.5 + 500 * 6 = 4500 billed token

gpt-5.4 prompt_tokens=1000, completion_tokens=500
user_quota = 1000 * 0.5 + 500 * 3 = 2000 billed token
```

### Profit accounting vs nguồn model cost

User quota và internal cost không còn cần bằng nhau.

Nếu nguồn model thực tế tính raw token 1:1 cho `gpt-5.5*` và `opus-4.8-thinking`, profit ratio theo từng request là:

```text
internal_cost_units ~= prompt_tokens + completion_tokens
user_charged_tokens = prompt_tokens * 1.5 + completion_tokens * 6  -- gpt-5.5*/Claude current hiện tại
profit_spread_units = user_charged_tokens - internal_cost_units
```

Ví dụ:

| Prompt | Completion | Internal raw-token cost | User charged | Spread |
| -----: | ---------: | ----------------------: | -----------: | -----: |
|  1,000 |        100 |                   1,100 |        2,100 | +1,000 |
|  1,000 |        500 |                   1,500 |        4,500 | +3,000 |
|  1,000 |      1,000 |                   2,000 |        7,500 | +5,500 |

Nếu nguồn model cũng tính output theo OpenAI-style multiplier, spread sẽ khác. Vì vậy nguồn model/VietAPI cost phải được đối soát riêng bằng báo cáo nội bộ, không dùng để quyết định trực tiếp user quota.

### Cấu hình New API mới

New API dùng `tiered_expr` để kiểm soát chính xác input/output multiplier và tránh fallback `ModelRatio = 37.5`.

Vì New API quy đổi expression theo `QuotaPerUnit = 500000`, hệ số expression map sang user quota như sau:

| Expression coefficient | User quota/token |
| ---------------------: | ---------------: |
|                   `12` |            `6.0` |
|                  `2.4` |            `1.2` |
|                    `6` |            `3.0` |
|                    `3` |            `1.5` |
|                    `2` |            `1.0` |
|                    `1` |            `0.5` |
|                  `0.5` |           `0.25` |

```text
billing_setting.billing_mode = {
  "gpt-5.4": "tiered_expr",
  "gpt-5.5": "tiered_expr",
  "gpt-5.5-xhigh": "tiered_expr",
  "gpt-5.6-sol": "tiered_expr",
  "gpt-5.6-terra": "tiered_expr",
  "glm-5.1": "tiered_expr",
  "glm-5.2": "tiered_expr",
  "minimax-m3": "tiered_expr",
  "opus-4.8": "tiered_expr",
  "opus-4.8-thinking": "tiered_expr",
  "claude-opus-4.8": "tiered_expr",
  "claude-opus-4.8-thinking": "tiered_expr"
}

billing_setting.billing_expr = {
  "gpt-5.4": "tier(\"openai_price_gpt54\", p * 1 + c * 6)",
  "gpt-5.5": "tier(\"openai_price_gpt55\", p * 3 + c * 12)",
  "gpt-5.5-xhigh": "tier(\"openai_price_gpt55\", p * 3 + c * 12)",
  "gpt-5.6-sol": "c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 4 + c * 12))",
  "gpt-5.6-terra": "c <= 0 ? tier(\"zero_output\", 0) : (tier(\"openai_price_gpt55\", p * 3 + c * 12))",
  "opus-4.8": "tier(\"openai_price_gpt55\", p * 3 + c * 12)",
  "opus-4.8-thinking": "tier(\"openai_price_gpt55\", p * 3 + c * 12)",
  "claude-opus-4.8": "tier(\"openai_price_gpt55\", p * 3 + c * 12)",
  "claude-opus-4.8-thinking": "tier(\"openai_price_gpt55\", p * 3 + c * 12)",
  "minimax-m3": "tier(\"user_token_1x\", p * 2 + c * 2)",
  "glm-5.2": "tier(\"user_token_0_5x\", p * 1 + c * 1)",
  "glm-5.1": "tier(\"user_token_0_25x\", p * 0.5 + c * 0.5)"
}
```

`gpt-5.5`/`gpt-5.5-xhigh` và `opus-4.8`/`opus-4.8-thinking`/`claude-opus-4.8`/`claude-opus-4.8-thinking` hiện chốt input 1.5x (`p * 3`, đổi từ 1.2x ngày 2026-07-12), output 6x. `gpt-5.6-sol` chốt input 2.0x (`p * 4`), `gpt-5.6-terra` input 1.5x (`p * 3`), cả hai output 6x (`c * 12`) như `gpt-5.5`. Các model chưa có bảng giá nguồn/chiến lược pricing đã chốt (`minimax-m3`, `glm-5.2`, `glm-5.1`) tạm giữ nguyên.

### Runtime target 2026-07-12 (input 1.5x)

GPT-5.5/Claude current input target là `1.5x` (`p * 3`), nâng từ `1.2x`. Applied to prod `inviv-k8s`/`oneapi` via `src/deploy/migration-2026-07-12-gpt55-opus48-input-1_5x.sql` — additive merge of `billing_setting.billing_expr`, six models only, output `c * 12` unchanged, zero-output guard preserved. Verified: exactly six keys changed `p * 2.4` → `p * 3`; other 11 model entries byte-identical.

#### Historical: runtime target 2026-07-01 (input 1.2x)

GPT-5.5/Claude current input target khi đó là `1.2x`. Migration `src/deploy/migration-2026-07-01-gpt55-claude48-input-1_2x.sql`. Superseded by the 2026-07-12 change above.

| Surface | Runtime state |
| --- | --- |
| Frontend image | Public portal derives display from `billing_expr`; no frontend rebuild required for the 1.5x change |
| Kubernetes deployment | DB-only change; New API has `MEMORY_CACHE_ENABLED=true`, picks up option changes without restart |
| DB migration | `src/deploy/migration-2026-07-12-gpt55-opus48-input-1_5x.sql`; applied manually to `new-api-postgres` |
| Runtime billing expr | GPT 5.5 and current Claude/Opus aliases = `tier("openai_price_gpt55", p * 3 + c * 12)` |
| Public portal | Derived display should read `Input 1.5x · Output 6x` |
| Known infra note | `https://api.1api.click/api/status` currently has external TLS/cert mismatch; in-cluster `http://new-api:3000/api/status` responds OK. |

Deployment reminder: `src/deploy/deploy.sh` only applies Kubernetes manifests and waits for rollouts. It does **not** auto-run SQL migration files. Apply billing migrations separately with `psql` against `new-api-postgres`.

### SQL verify runtime

Kiểm tra cấu hình billing đang chạy:

```sql
select key, value
from options
where key like 'billing_setting.%'
order by key;
```

Kiểm tra request mới có trừ đúng OpenAI-style user quota không:

```sql
select
  id,
  model_name,
  prompt_tokens,
  completion_tokens,
  quota,
  case
    when model_name like 'gpt-5.5%' then round(prompt_tokens * 1.5 + completion_tokens * 6.0)
    when model_name in ('opus-4.8','opus-4.8-thinking','claude-opus-4.8','claude-opus-4.8-thinking') then round(prompt_tokens * 1.5 + completion_tokens * 6.0)
    when model_name = 'gpt-5.4' then round(prompt_tokens * 0.5 + completion_tokens * 3.0)
    when model_name = 'glm-5.2' then round((prompt_tokens + completion_tokens) * 0.5)
    when model_name = 'glm-5.1' then round((prompt_tokens + completion_tokens) * 0.25)
    else prompt_tokens + completion_tokens
  end as expected_quota,
  quota - case
    when model_name like 'gpt-5.5%' then round(prompt_tokens * 1.5 + completion_tokens * 6.0)
    when model_name in ('opus-4.8','opus-4.8-thinking','claude-opus-4.8','claude-opus-4.8-thinking') then round(prompt_tokens * 1.5 + completion_tokens * 6.0)
    when model_name = 'gpt-5.4' then round(prompt_tokens * 0.5 + completion_tokens * 3.0)
    when model_name = 'glm-5.2' then round((prompt_tokens + completion_tokens) * 0.5)
    when model_name = 'glm-5.1' then round((prompt_tokens + completion_tokens) * 0.25)
    else prompt_tokens + completion_tokens
  end as delta,
  (other::jsonb)->>'billing_mode' as billing_mode,
  (other::jsonb)->>'matched_tier' as matched_tier
from logs
where type = 2
order by id desc
limit 20;
```

Pass criteria:

```text
billing_mode = tiered_expr
matched_tier = openai_price_gpt55 | openai_price_gpt54 | existing non-GPT tiers
delta = 0 for fresh requests after migration
```

### SQL report profit spread nội bộ

Nếu internal cost tạm xem là raw token 1:1 cho GPT nguồn hiện tại, **lọc từ thời điểm rollout** để không trộn log cũ trước migration:

```sql
-- Replace 101 with the first consume-log id after the OpenAI-price migration.
with usage as (
  select
    model_name,
    sum(prompt_tokens)::numeric as prompt_tokens,
    sum(completion_tokens)::numeric as completion_tokens,
    sum(quota)::numeric as user_charged_tokens
  from logs
  where type = 2
    and quota > 0
    and id >= 101
  group by model_name
), rated as (
  select
    model_name,
    prompt_tokens,
    completion_tokens,
    user_charged_tokens,
    case
      when model_name like 'gpt-5.5%' then prompt_tokens * 1.2 + completion_tokens
      when model_name in ('opus-4.8','opus-4.8-thinking','claude-opus-4.8','claude-opus-4.8-thinking') then prompt_tokens * 1.2 + completion_tokens
      when model_name = 'gpt-5.4' then prompt_tokens + completion_tokens
      when model_name = 'glm-5.2' then (prompt_tokens + completion_tokens) * 0.5
      when model_name = 'glm-5.1' then (prompt_tokens + completion_tokens) * 0.25
      else prompt_tokens + completion_tokens
    end as estimated_internal_cost_units
  from usage
)
select
  model_name,
  prompt_tokens,
  completion_tokens,
  user_charged_tokens,
  estimated_internal_cost_units,
  user_charged_tokens - estimated_internal_cost_units as estimated_spread_units,
  round(user_charged_tokens / nullif(estimated_internal_cost_units, 0), 4) as charge_to_cost_ratio
from rated
order by estimated_spread_units desc;
```

### Mô hình cost VietAPI Mega và profit planning

Giả định vận hành hiện tại từ user:

```text
VietAPI Mega = 1.200.000đ / tháng
Dung lượng = 80M raw token / ngày
1 quota unit = 1 raw/billed token đơn vị hiển thị trong portal
Tháng 30 ngày = 2.4B raw token capacity
Cost nguồn = 1.200.000 / 2.400M = 500đ / 1M raw token
```

Với các model đang tính input `1.5x`, output `6x` (đổi từ `1.2x` ngày 2026-07-12), số billed token bán ra trên cùng một raw-token capacity phụ thuộc tỷ lệ output:

```text
output_share = completion_tokens / (prompt_tokens + completion_tokens)
effective_billed_token_per_raw_token = 1.5 + 4.5 * output_share
```

| Output share | 80M raw token/ngày thành billed token/ngày | 2.4B raw token/tháng thành billed token/tháng |
| ------------: | ---------------------------------------: | -------------------------------------------: |
| 0%            | 80M                                      | 2.4B                                        |
| 10%           | 120M                                     | 3.6B                                        |
| 20%           | 160M                                     | 4.8B                                        |
| 33%           | ~213M                                    | ~6.4B                                       |
| 50%           | 280M                                     | 8.4B                                        |

Rule of thumb nội bộ:

```text
revenue = billed_tokens_sold_millions * package_price_per_1M_token
source_cost = raw_tokens_used_millions * 500đ
gross_profit = revenue - source_cost
```

Ví dụ safe capacity một gói Mega ở output share khoảng 33%:

```text
4 Power    = 2.0B billed token
6 Standard = 1.5B billed token
6 Starter  = 0.6B billed token
6 Mini     = 0.3B billed token
Total sell = 4.4B billed token
Revenue   = 4*549K + 6*299K + 6*129K + 6*69K = 5.178M
Cost      = 1.2M
Gross profit ~= 3.978M / Mega / month
Gross margin ~= 76.8%
```

Không bán 100% theoretical capacity ngay từ đầu vì VietAPI Mega reset theo ngày còn token pack 1API không reset và có thể bị burst. Khuyến nghị vận hành ban đầu: bán khoảng 70% capacity, giữ 30% buffer.

### Rollback về raw-token GPT billing cũ

```sql
update options
set value = '{"gpt-5.4":"tier(\"user_token_1x\", p * 2 + c * 2)","gpt-5.5":"tier(\"user_token_1x\", p * 2 + c * 2)","gpt-5.5-xhigh":"tier(\"user_token_1x\", p * 2 + c * 2)","opus-4.8-thinking":"tier(\"user_token_1x\", p * 2 + c * 2)","minimax-m3":"tier(\"user_token_1x\", p * 2 + c * 2)","glm-5.2":"tier(\"user_token_0_5x\", p * 1 + c * 1)","glm-5.1":"tier(\"user_token_0_25x\", p * 0.5 + c * 0.5)"}'
where key = 'billing_setting.billing_expr';
```

## 1. Gói tháng GPT-5.5 API

| Gói 1API | Token/ngày | Token/tháng |          Giá | Giá / 1M token nếu dùng full |
| -------- | ---------: | ----------: | -----------: | ---------------------------: |
| Plus     |   20M/ngày |  600M/tháng |   549K/tháng |                   ~915đ / 1M |
| Pro      |   40M/ngày |  1.2B/tháng |   879K/tháng |                   ~733đ / 1M |
| Ultra    |   60M/ngày |  1.8B/tháng | 1.199K/tháng |                   ~666đ / 1M |
| Max      |   80M/ngày |  2.4B/tháng | 1.549K/tháng |                   ~645đ / 1M |

### Quy tắc triển khai gói tháng

| Field DB             | Giá trị                                 |
| -------------------- | --------------------------------------- |
| `quota_reset_period` | `daily`                                 |
| `duration_unit`      | `month`                                 |
| `duration_value`     | `1`                                     |
| `currency`           | `VND`                                   |
| `model_list`         | `NULL` nếu áp dụng toàn bộ model active |

### Định vị gói tháng

#### 1API Plus

- **Giá:** 549K/tháng
- **Token:** 20M/ngày
- **Phù hợp:** cá nhân cần API GPT-5.5 để code, test tool, automation nhẹ.

#### 1API Pro

- **Giá:** 879K/tháng
- **Token:** 40M/ngày
- **Phù hợp:** developer dùng coding agent thường xuyên, workflow code hằng ngày.

#### 1API Ultra

- **Giá:** 1.199K/tháng
- **Token:** 60M/ngày
- **Phù hợp:** power user, freelancer, automation nặng hơn.

#### 1API Max

- **Giá:** 1.549K/tháng
- **Token:** 80M/ngày
- **Phù hợp:** team nhỏ, nhiều API key phụ, agent chạy liên tục.

---

## 2. Gói one-time / token pack

Gói one-time phải đắt hơn giá hiệu dụng của gói tháng vì khách có thể dùng linh hoạt, không bị reset hằng ngày và không cần subscription đều.

| Gói one-time | Token |  Giá | Giá / 1M token | Định vị                         |
| ------------ | ----: | ---: | -------------: | ------------------------------- |
| Mini         |   50M |  69K |   ~1.380đ / 1M | Test API / dùng ít              |
| Starter      |  100M | 129K |   ~1.290đ / 1M | Cá nhân dùng nhẹ                |
| Standard     |  250M | 299K |   ~1.196đ / 1M | Dùng không đều                  |
| Power        |  500M | 549K |   ~1.098đ / 1M | Gần Plus nhưng không reset/ngày |

### Quy tắc triển khai gói one-time

| Field DB             | Giá trị                                 |
| -------------------- | --------------------------------------- |
| `quota_reset_period` | `never`                                 |
| `duration_unit`      | `custom`                                |
| `custom_seconds`     | `3153600000` — tương đương 100 năm      |
| `currency`           | `VND`                                   |
| `upgrade_group`      | rỗng                                    |
| `model_list`         | `NULL` nếu áp dụng toàn bộ model active |

### Vì sao không giữ giá cũ

Bảng cũ:

| Gói cũ   | Token | Giá cũ |
| -------- | ----: | -----: |
| Mini     |   50M |    25K |
| Starter  |  110M |    50K |
| Standard |  250M |   100K |

Bảng cũ rẻ hơn quá nhiều so với subscription, khiến khách có lý do không mua gói tháng. Bảng mới tạo bậc giá hợp lý hơn:

```txt
Gói tháng = rẻ hơn theo token, phù hợp dùng đều.
Gói one-time = đắt hơn theo token, phù hợp dùng ít/không đều/không muốn subscription.
```

---

## 3. Bảng source of truth để sync DB

### Monthly plans

| title | price_amount | total_amount | quota_reset_period | sort_order | upgrade_group |
| ----- | -----------: | -----------: | ------------------ | ---------: | ------------- |
| Plus  |       549000 |     20000000 | daily              |         10 |               |
| Pro   |       879000 |     40000000 | daily              |         20 |               |
| Ultra |      1199000 |     60000000 | daily              |         30 |               |
| Max   |      1549000 |     80000000 | daily              |         40 | max           |

### One-time packs

| title    | price_amount | total_amount | quota_reset_period | sort_order | upgrade_group |
| -------- | -----------: | -----------: | ------------------ | ---------: | ------------- |
| Mini     |        69000 |     50000000 | never              |         10 |               |
| Starter  |       129000 |    100000000 | never              |         20 |               |
| Standard |       299000 |    250000000 | never              |         30 |               |
| Power    |       549000 |    500000000 | never              |         40 |               |

---

## 4. Thông điệp bán hàng public

1API không định vị là nguồn API rẻ nhất. 1API là lớp **managed API** giúp người dùng Việt dùng GPT-5.5 cho code và automation dễ hơn:

- API key riêng.
- Dashboard theo dõi usage.
- Quota rõ ràng theo ngày hoặc theo gói one-time.
- Log sử dụng.
- Hỗ trợ setup Claude Code / Codex / Cursor / OpenCode.
- Hỗ trợ tiếng Việt.
- Có thể quản lý key phụ cho team.

Câu chốt:

> Nếu bạn cần API để code, chạy agent hoặc automation với token rõ ràng, dashboard usage và hỗ trợ tiếng Việt, chọn 1API.

---

## 5. Files triển khai liên quan

- Backend seed/update monthly + one-time:
  - `src/potal/backend/src/main/java/com/example/potal/ProvisioningController.java`
- Apply pricing endpoint:
  - `src/potal/backend/src/main/java/com/example/potal/PricingController.java`
- Public/user/admin portal:
  - `src/potal/frontend/src/App.vue`
  - `src/potal/frontend/src/views/LandingPage.vue`
  - `src/potal/frontend/src/locales/vi.ts`
  - `src/potal/frontend/src/locales/en.ts`
- Companion New API admin:
  - `new-api-user-portal/admin.html`
  - `new-api-user-portal/server.mjs`
- DB migrations:
  - `src/deploy/migration-2026-06-27-update-1api-gpt55-plans.sql`
  - `src/deploy/migration-2026-06-28-update-1api-one-time-packs.sql`
  - `src/deploy/migration-2026-06-28-openai-price-user-billing.sql`
  - `src/deploy/migration-2026-06-29-gpt55-claude48-input-1_5x.sql` — historical GPT/Claude input 1.5x migration; superseded by later overrides.
  - `src/deploy/migration-2026-06-30-gpt55-input-1x.sql` — historical GPT-5.5/GPT-5.5 X-HIGH input 1x override.
  - `src/deploy/migration-2026-07-01-gpt55-claude48-input-1_2x.sql` — historical GPT-5.5 and Claude/Opus 4.8 input 1.2x override; superseded by the 2026-07-12 1.5x migration.
  - `src/deploy/migration-2026-07-12-gpt55-opus48-input-1_5x.sql` — current target GPT-5.5 and Claude/Opus 4.8 input 1.5x override (`p * 3`, output `c * 12` unchanged). Applied to prod 2026-07-12.
