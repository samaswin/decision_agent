# Advanced Rule DSL Operators

This document describes the advanced operators available in the Decision Agent Rule DSL. These operators extend the basic comparison operators (`eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `in`, `present`, `blank`) with specialized functionality for strings, numbers, dates, collections, and geospatial data.

## Table of Contents

- [String Operators](#string-operators)
- [Numeric Operators](#numeric-operators)
- [Date/Time Operators](#datetime-operators)
- [Collection Operators](#collection-operators)
- [Geospatial Operators](#geospatial-operators)
- [Examples](#examples)

---

## String Operators

### `contains`

Checks if a string contains a substring (case-sensitive).

**Syntax:**
```json
{
  "field": "message",
  "op": "contains",
  "value": "error"
}
```

**Example:**
```json
{
  "version": "1.0",
  "ruleset": "error_detection",
  "rules": [
    {
      "id": "error_alert",
      "if": {
        "field": "log_message",
        "op": "contains",
        "value": "ERROR"
      },
      "then": {
        "decision": "send_alert",
        "weight": 0.9,
        "reason": "Error detected in log message"
      }
    }
  ]
}
```

**Behavior:**
- Case-sensitive matching
- Both field and value must be strings
- Returns `false` if field is not a string

---

### `starts_with`

Checks if a string starts with a specified prefix (case-sensitive).

**Syntax:**
```json
{
  "field": "error_code",
  "op": "starts_with",
  "value": "ERR"
}
```

**Example:**
```json
{
  "field": "transaction_id",
  "op": "starts_with",
  "value": "TXN-"
}
```

**Behavior:**
- Case-sensitive matching
- Both field and value must be strings

---

### `ends_with`

Checks if a string ends with a specified suffix (case-sensitive).

**Syntax:**
```json
{
  "field": "filename",
  "op": "ends_with",
  "value": ".pdf"
}
```

**Example:**
```json
{
  "id": "pdf_processor",
  "if": {
    "field": "document.filename",
    "op": "ends_with",
    "value": ".pdf"
  },
  "then": {
    "decision": "route_to_pdf_processor",
    "weight": 1.0
  }
}
```

**Behavior:**
- Case-sensitive matching
- Both field and value must be strings

---

### `matches`

Matches a string against a regular expression pattern.

**Syntax:**
```json
{
  "field": "email",
  "op": "matches",
  "value": "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
}
```

**Example:**
```json
{
  "id": "validate_email",
  "if": {
    "field": "user.email",
    "op": "matches",
    "value": "^[a-z0-9._%+-]+@company\\.com$"
  },
  "then": {
    "decision": "employee_email",
    "weight": 1.0,
    "reason": "Email is from company domain"
  }
}
```

**Behavior:**
- Value can be a regex string or Regexp object
- Invalid regex patterns return `false` (fail-safe)
- Field must be a string

**Common Patterns:**
- Email: `^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$`
- Phone (US): `^\\(\\d{3}\\)\\s?\\d{3}-\\d{4}$`
- UUID: `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`
- IP Address: `^((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.?\\b){4}$`

---

## Numeric Operators

### `between`

Checks if a numeric value is between a minimum and maximum value (inclusive).

**Syntax (Array Format):**
```json
{
  "field": "age",
  "op": "between",
  "value": [18, 65]
}
```

**Syntax (Hash Format):**
```json
{
  "field": "score",
  "op": "between",
  "value": { "min": 0, "max": 100 }
}
```

**Example:**
```json
{
  "id": "age_verification",
  "if": {
    "field": "applicant.age",
    "op": "between",
    "value": [21, 70]
  },
  "then": {
    "decision": "eligible",
    "weight": 0.9,
    "reason": "Applicant age is within acceptable range"
  }
}
```

**Behavior:**
- Boundary values are included (closed interval)
- Field must be numeric
- Supports both integer and floating-point numbers

---

### `modulo`

Checks if a value modulo a divisor equals a specified remainder.

**Syntax (Array Format):**
```json
{
  "field": "order_id",
  "op": "modulo",
  "value": [2, 0]
}
```

**Syntax (Hash Format):**
```json
{
  "field": "customer_id",
  "op": "modulo",
  "value": { "divisor": 10, "remainder": 5 }
}
```

**Example - Even Numbers:**
```json
{
  "id": "even_id_routing",
  "if": {
    "field": "user_id",
    "op": "modulo",
    "value": [2, 0]
  },
  "then": {
    "decision": "route_to_server_a",
    "weight": 1.0,
    "reason": "Route even user IDs to server A"
  }
}
```

**Example - A/B Testing:**
```json
{
  "id": "ab_test_variant_b",
  "if": {
    "field": "session_id",
    "op": "modulo",
    "value": { "divisor": 3, "remainder": 1 }
  },
  "then": {
    "decision": "show_variant_b",
    "weight": 1.0
  }
}
```

**Use Cases:**
- A/B testing distribution
- Load balancing
- Sharding logic
- Identifying patterns (even/odd numbers)

---

## Statistical Aggregations

### `sum`

Calculates the sum of numeric array elements.

**Syntax:**
```json
{
  "field": "transaction.amounts",
  "op": "sum",
  "value": 1000
}
```

**Syntax (with comparison):**
```json
{
  "field": "prices",
  "op": "sum",
  "value": { "min": 50, "max": 150 }
}
```

**Example:**
```json
{
  "id": "total_amount_check",
  "if": {
    "field": "order.items.prices",
    "op": "sum",
    "value": { "gte": 100 }
  },
  "then": {
    "decision": "free_shipping",
    "weight": 1.0,
    "reason": "Order total exceeds $100"
  }
}
```

**Behavior:**
- Field must be an array
- Only numeric values are included in calculation
- Returns `false` if array is empty or contains no numeric values
- Supports direct comparison or hash with comparison operators (`min`, `max`, `gt`, `lt`, `gte`, `lte`, `eq`)

---

### `average` / `mean`

Calculates the average (mean) of numeric array elements.

**Syntax:**
```json
{
  "field": "response_times",
  "op": "average",
  "value": 150
}
```

**Example:**
```json
{
  "id": "latency_check",
  "if": {
    "field": "api.response_times",
    "op": "average",
    "value": { "lt": 200 }
  },
  "then": {
    "decision": "acceptable_latency",
    "weight": 0.9
  }
}
```

---

### `median`

Calculates the median value of a numeric array.

**Syntax:**
```json
{
  "field": "scores",
  "op": "median",
  "value": 75
}
```

**Example:**
```json
{
  "id": "median_score_check",
  "if": {
    "field": "test.scores",
    "op": "median",
    "value": { "gte": 70 }
  },
  "then": {
    "decision": "passing_grade",
    "weight": 0.8
  }
}
```

---

### `stddev` / `standard_deviation`

Calculates the standard deviation of a numeric array.

**Syntax:**
```json
{
  "field": "latencies",
  "op": "stddev",
  "value": { "lt": 50 }
}
```

**Example:**
```json
{
  "id": "consistency_check",
  "if": {
    "field": "performance.metrics",
    "op": "stddev",
    "value": { "lt": 25 }
  },
  "then": {
    "decision": "stable_performance",
    "weight": 0.9
  }
}
```

**Behavior:**
- Requires at least 2 numeric values
- Returns `false` if array has fewer than 2 numeric elements

---

### `variance`

Calculates the variance of a numeric array.

**Syntax:**
```json
{
  "field": "scores",
  "op": "variance",
  "value": { "lt": 100 }
}
```

---

### `percentile`

Calculates the Nth percentile of a numeric array.

**Syntax:**
```json
{
  "field": "response_times",
  "op": "percentile",
  "value": { "percentile": 95, "threshold": 200 }
}
```

**Example:**
```json
{
  "id": "p95_latency_alert",
  "if": {
    "field": "api.response_times",
    "op": "percentile",
    "value": { "percentile": 95, "gt": 500 }
  },
  "then": {
    "decision": "high_latency_alert",
    "weight": 0.95
  }
}
```

**Supported Parameters:**
- `percentile`: Number between 0-100 (required)
- `threshold`: Direct comparison value
- `gt`, `lt`, `gte`, `lte`, `eq`: Comparison operators

---

### `count`

Counts the number of elements in an array.

**Syntax:**
```json
{
  "field": "errors",
  "op": "count",
  "value": { "gte": 10 }
}
```

**Example:**
```json
{
  "id": "error_threshold",
  "if": {
    "field": "recent_errors",
    "op": "count",
    "value": { "gte": 5 }
  },
  "then": {
    "decision": "alert_required",
    "weight": 1.0
  }
}
```

---

## Date/Time Operators

All date/time operators accept dates in multiple formats:
- ISO 8601 strings: `"2025-12-31"` or `"2025-12-31T23:59:59Z"`
- Ruby Time objects
- Ruby Date objects
- Ruby DateTime objects

### `before_date`

Checks if a date is before a specified date.

**Syntax:**
```json
{
  "field": "expires_at",
  "op": "before_date",
  "value": "2026-01-01"
}
```

**Example:**
```json
{
  "id": "check_expiration",
  "if": {
    "field": "license.expires_at",
    "op": "before_date",
    "value": "2025-12-31"
  },
  "then": {
    "decision": "license_valid",
    "weight": 0.8,
    "reason": "License has not expired"
  }
}
```

---

### `after_date`

Checks if a date is after a specified date.

**Syntax:**
```json
{
  "field": "created_at",
  "op": "after_date",
  "value": "2024-01-01"
}
```

**Example:**
```json
{
  "id": "recent_account",
  "if": {
    "field": "account.created_at",
    "op": "after_date",
    "value": "2024-06-01"
  },
  "then": {
    "decision": "new_user_promotion",
    "weight": 0.9,
    "reason": "Account created recently"
  }
}
```

---

### `within_days`

Checks if a date is within N days from the current time (past or future).

**Syntax:**
```json
{
  "field": "event_date",
  "op": "within_days",
  "value": 7
}
```

**Example:**
```json
{
  "id": "upcoming_event_reminder",
  "if": {
    "field": "appointment.scheduled_at",
    "op": "within_days",
    "value": 3
  },
  "then": {
    "decision": "send_reminder",
    "weight": 1.0,
    "reason": "Appointment is within 3 days"
  }
}
```

**Behavior:**
- Calculates absolute difference (works for both past and future dates)
- Value is the number of days
- Uses current time as reference point

---

### `day_of_week`

Checks if a date falls on a specified day of the week.

**Syntax (String Format):**
```json
{
  "field": "delivery_date",
  "op": "day_of_week",
  "value": "monday"
}
```

**Syntax (Numeric Format):**
```json
{
  "field": "delivery_date",
  "op": "day_of_week",
  "value": 1
}
```

**Example:**
```json
{
  "id": "weekend_pricing",
  "if": {
    "any": [
      { "field": "booking_date", "op": "day_of_week", "value": "saturday" },
      { "field": "booking_date", "op": "day_of_week", "value": "sunday" }
    ]
  },
  "then": {
    "decision": "apply_weekend_discount",
    "weight": 1.0,
    "reason": "Weekend booking discount"
  }
}
```

**Supported Values:**
- **Strings:** `"sunday"`, `"monday"`, `"tuesday"`, `"wednesday"`, `"thursday"`, `"friday"`, `"saturday"`
- **Abbreviations:** `"sun"`, `"mon"`, `"tue"`, `"wed"`, `"thu"`, `"fri"`, `"sat"`
- **Numbers:** `0` (Sunday) through `6` (Saturday)

---

## Duration Calculations

### `duration_seconds`

Calculates the duration between two dates in seconds.

**Syntax:**
```json
{
  "field": "session.start_time",
  "op": "duration_seconds",
  "value": { "end": "now", "max": 3600 }
}
```

**Example:**
```json
{
  "id": "session_timeout",
  "if": {
    "field": "session.last_activity",
    "op": "duration_seconds",
    "value": { "end": "now", "gt": 1800 }
  },
  "then": {
    "decision": "session_expired",
    "weight": 1.0
  }
}
```

**Parameters:**
- `end`: `"now"` or a field path (e.g., `"session.end_time"`)
- `min`, `max`, `gt`, `lt`, `gte`, `lte`: Comparison operators

---

### `duration_minutes`, `duration_hours`, `duration_days`

Similar to `duration_seconds` but returns duration in minutes, hours, or days respectively.

**Example:**
```json
{
  "field": "order.created_at",
  "op": "duration_hours",
  "value": { "end": "now", "gte": 24 }
}
```

---

## Date Arithmetic

### `add_days`

Adds days to a date and compares the result.

**Syntax:**
```json
{
  "field": "order.created_at",
  "op": "add_days",
  "value": { "days": 7, "compare": "lt", "target": "now" }
}
```

**Example:**
```json
{
  "id": "trial_expiring_soon",
  "if": {
    "field": "trial.started_at",
    "op": "add_days",
    "value": { "days": 7, "compare": "lte", "target": "now" }
  },
  "then": {
    "decision": "trial_expiring",
    "weight": 0.9
  }
}
```

**Parameters:**
- `days`: Number of days to add
- `target`: `"now"` or a field path
- `compare`: Comparison operator (`"eq"`, `"gt"`, `"lt"`, `"gte"`, `"lte"`)
- Or use direct operators: `eq`, `gt`, `lt`, `gte`, `lte`

---

### `subtract_days`, `add_hours`, `subtract_hours`, `add_minutes`, `subtract_minutes`

Similar to `add_days` but for subtracting days or adding/subtracting hours/minutes.

**Example:**
```json
{
  "field": "deadline",
  "op": "subtract_hours",
  "value": { "hours": 1, "compare": "gt", "target": "now" }
}
```

---

## Time Component Extraction

### `hour_of_day`

Extracts the hour of day (0-23) from a date.

**Syntax:**
```json
{
  "field": "event.timestamp",
  "op": "hour_of_day",
  "value": { "min": 9, "max": 17 }
}
```

**Example:**
```json
{
  "id": "business_hours",
  "if": {
    "field": "request.timestamp",
    "op": "hour_of_day",
    "value": { "gte": 9, "lte": 17 }
  },
  "then": {
    "decision": "within_business_hours",
    "weight": 1.0
  }
}
```

---

### `day_of_month`, `month`, `year`, `week_of_year`

Similar to `hour_of_day` but extracts day of month (1-31), month (1-12), year, or week of year (1-52).

**Example:**
```json
{
  "field": "event.date",
  "op": "month",
  "value": 12
}
```

---

## Rate Calculations

### `rate_per_second`

Calculates the rate per second from an array of timestamps.

**Syntax:**
```json
{
  "field": "request_timestamps",
  "op": "rate_per_second",
  "value": { "max": 10 }
}
```

**Example:**
```json
{
  "id": "rate_limit_check",
  "if": {
    "field": "user.recent_request_timestamps",
    "op": "rate_per_second",
    "value": { "max": 10 }
  },
  "then": {
    "decision": "rate_limit_exceeded",
    "weight": 1.0
  }
}
```

**Behavior:**
- Field must be an array of timestamps
- Requires at least 2 timestamps
- Calculates rate as: `count / time_span_in_seconds`

---

### `rate_per_minute`, `rate_per_hour`

Similar to `rate_per_second` but calculates rate per minute or per hour.

---

## Moving Window Calculations

### `moving_average`

Calculates the moving average over a specified window.

**Syntax:**
```json
{
  "field": "metrics.values",
  "op": "moving_average",
  "value": { "window": 5, "threshold": 100 }
}
```

**Example:**
```json
{
  "id": "trend_analysis",
  "if": {
    "field": "performance.metrics",
    "op": "moving_average",
    "value": { "window": 10, "gt": 50 }
  },
  "then": {
    "decision": "increasing_trend",
    "weight": 0.8
  }
}
```

**Parameters:**
- `window`: Number of elements to include (required)
- `threshold`, `gt`, `lt`, `gte`, `lte`, `eq`: Comparison operators

---

### `moving_sum`, `moving_max`, `moving_min`

Similar to `moving_average` but calculates moving sum, max, or min over the window.

---

## Financial Calculations

### `compound_interest`

Calculates compound interest: `A = P(1 + r/n)^(nt)`

**Syntax:**
```json
{
  "field": "principal",
  "op": "compound_interest",
  "value": { "rate": 0.05, "periods": 12, "result": 1050 }
}
```

**Example:**
```json
{
  "id": "investment_check",
  "if": {
    "field": "investment.principal",
    "op": "compound_interest",
    "value": { "rate": 0.05, "periods": 12, "gt": 1000 }
  },
  "then": {
    "decision": "profitable_investment",
    "weight": 0.9
  }
}
```

**Parameters:**
- `rate`: Interest rate (e.g., 0.05 for 5%)
- `periods`: Number of compounding periods
- `result`: Expected result (optional, for exact match)
- `gt`, `lt`, `threshold`: Comparison operators

---

### `present_value`

Calculates present value: `PV = FV / (1 + r)^n`

**Syntax:**
```json
{
  "field": "future_value",
  "op": "present_value",
  "value": { "rate": 0.05, "periods": 10, "result": 613.91 }
}
```

---

### `future_value`

Calculates future value: `FV = PV * (1 + r)^n`

**Syntax:**
```json
{
  "field": "present_value",
  "op": "future_value",
  "value": { "rate": 0.05, "periods": 10, "result": 1628.89 }
}
```

---

### `payment`

Calculates loan payment (PMT): `PMT = P * [r(1+r)^n] / [(1+r)^n - 1]`

**Syntax:**
```json
{
  "field": "loan.principal",
  "op": "payment",
  "value": { "rate": 0.05, "periods": 12, "result": 100 }
}
```

---

## String Aggregations

### `join`

Joins an array of strings with a separator.

**Syntax:**
```json
{
  "field": "tags",
  "op": "join",
  "value": { "separator": ",", "result": "tag1,tag2,tag3" }
}
```

**Example:**
```json
{
  "id": "tag_formatting",
  "if": {
    "field": "article.tags",
    "op": "join",
    "value": { "separator": ",", "contains": "important" }
  },
  "then": {
    "decision": "has_important_tag",
    "weight": 0.8
  }
}
```

**Parameters:**
- `separator`: String to join with (default: `","`)
- `result`: Expected joined string (for exact match)
- `contains`: Substring to check for in joined string

---

### `length`

Gets the length of a string or array.

**Syntax:**
```json
{
  "field": "description",
  "op": "length",
  "value": { "max": 500 }
}
```

**Example:**
```json
{
  "id": "description_length",
  "if": {
    "field": "product.description",
    "op": "length",
    "value": { "min": 10, "max": 500 }
  },
  "then": {
    "decision": "valid_description",
    "weight": 1.0
  }
}
```

---

## Collection Operators

### `contains_all`

Checks if an array contains all of the specified elements.

**Syntax:**
```json
{
  "field": "permissions",
  "op": "contains_all",
  "value": ["read", "write"]
}
```

**Example:**
```json
{
  "id": "admin_access",
  "if": {
    "field": "user.permissions",
    "op": "contains_all",
    "value": ["read", "write", "delete"]
  },
  "then": {
    "decision": "grant_admin_access",
    "weight": 1.0,
    "reason": "User has all required permissions"
  }
}
```

**Behavior:**
- Both field and value must be arrays
- Order doesn't matter
- Field can contain additional elements

---

### `contains_any`

Checks if an array contains any of the specified elements.

**Syntax:**
```json
{
  "field": "tags",
  "op": "contains_any",
  "value": ["urgent", "critical", "emergency"]
}
```

**Example:**
```json
{
  "id": "priority_escalation",
  "if": {
    "field": "ticket.tags",
    "op": "contains_any",
    "value": ["urgent", "critical"]
  },
  "then": {
    "decision": "escalate_to_manager",
    "weight": 0.95,
    "reason": "Ticket has priority tag"
  }
}
```

**Behavior:**
- Both field and value must be arrays
- Returns `true` if at least one element matches

---

### `intersects`

Checks if two arrays have any common elements (set intersection).

**Syntax:**
```json
{
  "field": "user_roles",
  "op": "intersects",
  "value": ["admin", "moderator", "super_user"]
}
```

**Example:**
```json
{
  "id": "elevated_role_check",
  "if": {
    "field": "account.roles",
    "op": "intersects",
    "value": ["admin", "moderator"]
  },
  "then": {
    "decision": "allow_moderation_features",
    "weight": 1.0
  }
}
```

**Behavior:**
- Equivalent to `contains_any` but semantically indicates set comparison
- Returns `true` if intersection is non-empty

---

### `subset_of`

Checks if an array is a subset of another array (all elements are contained).

**Syntax:**
```json
{
  "field": "selected_options",
  "op": "subset_of",
  "value": ["option_a", "option_b", "option_c", "option_d"]
}
```

**Example:**
```json
{
  "id": "validate_selection",
  "if": {
    "field": "form.selected_features",
    "op": "subset_of",
    "value": ["feature_a", "feature_b", "feature_c"]
  },
  "then": {
    "decision": "valid_selection",
    "weight": 1.0,
    "reason": "All selected features are valid options"
  }
}
```

**Behavior:**
- Returns `true` if all elements in the field array exist in the value array
- Empty array is a subset of any array

---

## Geospatial Operators

### `within_radius`

Checks if a geographic point is within a specified radius of a center point.

**Syntax:**
```json
{
  "field": "location",
  "op": "within_radius",
  "value": {
    "center": { "lat": 40.7128, "lon": -74.0060 },
    "radius": 10
  }
}
```

**Coordinate Formats:**

**Hash Format:**
```json
{ "lat": 40.7128, "lon": -74.0060 }
{ "latitude": 40.7128, "longitude": -74.0060 }
{ "lat": 40.7128, "lng": -74.0060 }
```

**Array Format:**
```json
[40.7128, -74.0060]  // [latitude, longitude]
```

**Example:**
```json
{
  "id": "local_delivery",
  "if": {
    "field": "delivery.address.coordinates",
    "op": "within_radius",
    "value": {
      "center": { "lat": 37.7749, "lon": -122.4194 },
      "radius": 25
    }
  },
  "then": {
    "decision": "offer_same_day_delivery",
    "weight": 0.9,
    "reason": "Within 25km of distribution center"
  }
}
```

**Behavior:**
- Distance calculated using Haversine formula
- Radius is in kilometers
- Returns `false` if coordinates are invalid or missing

**Use Cases:**
- Delivery zone validation
- Store locator
- Geofencing
- Proximity-based routing

---

### `in_polygon`

Checks if a geographic point is inside a polygon using the ray casting algorithm.

**Syntax:**
```json
{
  "field": "location",
  "op": "in_polygon",
  "value": [
    { "lat": 40.0, "lon": -74.0 },
    { "lat": 41.0, "lon": -74.0 },
    { "lat": 41.0, "lon": -73.0 },
    { "lat": 40.0, "lon": -73.0 }
  ]
}
```

**Example - Service Area:**
```json
{
  "id": "service_area_check",
  "if": {
    "field": "customer.location",
    "op": "in_polygon",
    "value": [
      { "lat": 40.5, "lon": -74.5 },
      { "lat": 41.5, "lon": -74.5 },
      { "lat": 41.5, "lon": -73.0 },
      { "lat": 40.5, "lon": -73.0 }
    ]
  },
  "then": {
    "decision": "within_service_area",
    "weight": 1.0,
    "reason": "Customer is within our service area"
  }
}
```

**Example - Complex Boundary:**
```json
{
  "field": "store.location",
  "op": "in_polygon",
  "value": [
    [37.7749, -122.4194],
    [37.7849, -122.4094],
    [37.7949, -122.4194],
    [37.7849, -122.4294]
  ]
}
```

**Behavior:**
- Polygon must have at least 3 vertices
- Works with both hash and array coordinate formats
- Polygon is automatically closed (last point connects to first)
- Uses ray casting algorithm for point-in-polygon test

**Use Cases:**
- Service area boundaries
- Zoning validation
- Regulatory compliance zones
- Custom geographic regions

---

## Examples

### Complex Multi-Operator Rule

```json
{
  "version": "1.0",
  "ruleset": "fraud_detection",
  "rules": [
    {
      "id": "high_risk_transaction",
      "if": {
        "all": [
          {
            "field": "transaction.amount",
            "op": "between",
            "value": [1000, 10000]
          },
          {
            "field": "user.email",
            "op": "matches",
            "value": "^[a-z0-9._-]+@(gmail|yahoo|hotmail)\\.(com|net)$"
          },
          {
            "field": "user.account_age_days",
            "op": "lt",
            "value": 30
          },
          {
            "any": [
              {
                "field": "transaction.location",
                "op": "within_radius",
                "value": {
                  "center": { "lat": 40.7128, "lon": -74.0060 },
                  "radius": 100
                }
              },
              {
                "field": "user.risk_flags",
                "op": "contains_any",
                "value": ["vpn", "proxy", "tor"]
              }
            ]
          }
        ]
      },
      "then": {
        "decision": "require_additional_verification",
        "weight": 0.95,
        "reason": "High-risk transaction pattern detected"
      }
    }
  ]
}
```

### Email Domain Validation

```json
{
  "id": "corporate_email",
  "if": {
    "any": [
      { "field": "email", "op": "ends_with", "value": "@company.com" },
      { "field": "email", "op": "ends_with", "value": "@subsidiary.com" },
      { "field": "email", "op": "matches", "value": "^[a-z.]+@partner\\.(com|net)$" }
    ]
  },
  "then": {
    "decision": "grant_internal_access",
    "weight": 1.0
  }
}
```

### Scheduled Maintenance Window

```json
{
  "id": "maintenance_window",
  "if": {
    "all": [
      {
        "any": [
          { "field": "scheduled_time", "op": "day_of_week", "value": "saturday" },
          { "field": "scheduled_time", "op": "day_of_week", "value": "sunday" }
        ]
      },
      {
        "field": "scheduled_time",
        "op": "within_days",
        "value": 7
      }
    ]
  },
  "then": {
    "decision": "approve_maintenance",
    "weight": 0.9,
    "reason": "Scheduled during weekend maintenance window"
  }
}
```

### Delivery Zone Routing

```json
{
  "version": "1.0",
  "ruleset": "delivery_routing",
  "rules": [
    {
      "id": "zone_a_local",
      "if": {
        "field": "delivery_address.coordinates",
        "op": "in_polygon",
        "value": [
          { "lat": 40.7, "lon": -74.1 },
          { "lat": 40.8, "lon": -74.1 },
          { "lat": 40.8, "lon": -73.9 },
          { "lat": 40.7, "lon": -73.9 }
        ]
      },
      "then": {
        "decision": "route_to_zone_a",
        "weight": 1.0,
        "reason": "Address is in Zone A delivery polygon"
      }
    },
    {
      "id": "zone_b_radius",
      "if": {
        "field": "delivery_address.coordinates",
        "op": "within_radius",
        "value": {
          "center": { "lat": 40.75, "lon": -73.95 },
          "radius": 5
        }
      },
      "then": {
        "decision": "route_to_zone_b",
        "weight": 0.9,
        "reason": "Within 5km of Zone B distribution center"
      }
    }
  ]
}
```

### Permission-Based Access Control

```json
{
  "id": "feature_access",
  "if": {
    "all": [
      {
        "field": "user.permissions",
        "op": "contains_all",
        "value": ["feature_a_read", "feature_a_write"]
      },
      {
        "field": "user.roles",
        "op": "intersects",
        "value": ["power_user", "admin", "developer"]
      },
      {
        "field": "user.subscription_tier",
        "op": "in",
        "value": ["premium", "enterprise"]
      }
    ]
  },
  "then": {
    "decision": "grant_feature_a_access",
    "weight": 1.0,
    "reason": "User has required permissions and role"
  }
}
```

---

## Best Practices

### Performance Considerations

1. **String Operations**: `contains`, `starts_with`, and `ends_with` are faster than `matches`
2. **Geospatial**: Prefer `within_radius` for circular areas, `in_polygon` for irregular shapes
3. **Collections**: Use `contains_any` instead of multiple `eq` conditions in an `any` block

### Performance Benchmarks

**Last Updated: December 19, 2024**

Performance results from running `examples/advanced_operators_performance.rb` with 10,000 iterations:

| Operator Type | Throughput | Latency | Performance vs Basic |
|--------------|------------|---------|----------------------|
| Basic Operators (gt, eq, lt) | 7,904/sec | 0.127ms | Baseline |
| String Operators | 9,111/sec | 0.110ms | **+15.27% faster** |
| Numeric Operators | 6,994/sec | 0.143ms | -11.51% slower |
| Collection Operators | 5,810/sec | 0.172ms | -26.5% slower |
| Date Operators | 9,054/sec | 0.110ms | **+14.54% faster** |
| Geospatial Operators | 7,891/sec | 0.127ms | -0.17% (negligible) |
| Complex (all combined) | 4,516/sec | 0.221ms | -42.86% slower |

**Key Findings:**
- String operators perform **15.27% faster** than basic operators (likely due to early exit optimizations)
- Date operators perform **14.54% faster** than basic operators (fast-path parsing and caching)
- Geospatial operators show negligible performance difference (-0.17%)
- Collection operators improved from -72.2% to -26.5% (45.7% improvement) using Set-based lookups
- Numeric operators use epsilon comparison for more accurate floating-point math
- Complex rules combining many operators show expected slowdown (~43%)

**Optimizations Implemented:**
- ✅ Fast-path date parsing for ISO8601 formats (YYYY-MM-DD, YYYY-MM-DDTHH:MM:SS)
- ✅ Fast-path date comparison when values are already Time/Date objects (no parsing needed)
- ✅ Parameter parsing caching (range, modulo, etc.)
- ✅ Geospatial calculation caching with coordinate precision rounding
- ✅ Single-pass array aggregations (sum, average)
- ✅ **Set-based collection operators** (contains_all, contains_any, intersects, subset_of) for O(1) lookups instead of O(n)
- ✅ **Epsilon comparison** for numeric operators (sin, cos, tan, sqrt, exp, log, power) instead of round(10)
- ✅ Thread-safe caching for regex, dates, paths, and parameters

**Performance Notes:**
- Regex matching uses caching for repeated patterns
- Date parsing uses fast-path for ISO8601 and caching for all formats
- Geospatial calculations (Haversine) are cached with coordinate precision
- Statistical aggregations iterate over arrays (inherently more expensive)
- Complex mathematical functions use native Ruby Math library

### Error Handling

All operators are designed to fail safely:
- Invalid regex patterns return `false`
- Type mismatches return `false`
- Missing or nil values return `false`
- Malformed coordinates return `false`

### Validation

The schema validator ensures:
- All operators are recognized before evaluation
- Required fields are present
- Value types are appropriate for the operator

---

## Migration from Basic Operators

### Before (Multiple Rules):
```json
{
  "any": [
    { "field": "status", "op": "eq", "value": "urgent" },
    { "field": "status", "op": "eq", "value": "critical" },
    { "field": "status", "op": "eq", "value": "emergency" }
  ]
}
```

### After (Single Rule):
```json
{
  "field": "status",
  "op": "in",
  "value": ["urgent", "critical", "emergency"]
}
```

### Or Even Better (with tags array):
```json
{
  "field": "tags",
  "op": "contains_any",
  "value": ["urgent", "critical", "emergency"]
}
```

---

## Web UI Support

All advanced operators are fully supported in the DecisionAgent Web UI:

- **Visual Builder** - All operators available in dropdown menus, organized by category
- **Smart Placeholders** - Context-aware placeholders guide you on the expected value format
- **Helpful Hints** - Hover over value fields to see format examples
- **Example Rules** - Load example rules showcasing the new operators

Launch the Web UI:
```bash
decision_agent web
```

Or mount in your Rails app:
```ruby
mount DecisionAgent::Web::Server, at: '/decision_agent'
```

## See Also

- [API Contract](API_CONTRACT.md) - Core API documentation
- [Thread Safety](THREAD_SAFETY.md) - Concurrency considerations
- [Performance](PERFORMANCE_AND_THREAD_SAFETY.md) - Performance optimization
- [Web UI](WEB_UI.md) - Visual rule builder documentation
