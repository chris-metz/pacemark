# Pacemark

A macOS menu bar app that shows at a glance how much of the usage limits of your own AI subscriptions is already used, and whether you are on pace.

## Providers and limits

**Provider**:
An AI service whose limits Pacemark can show, such as Claude, Codex, Kimi or Grok.
_Avoid_: vendor, service, account

**Enabled provider**:
A provider the user has selected for monitoring in Pacemark, included in Overview and given its own provider tab.
_Avoid_: active provider, connected provider

**Limit**:
A provider's usage cap measured over a window. Its utilization can be known even when its reset time is not.
_Avoid_: quota, budget, allowance

**Window**:
The span of time over which a limit is measured (e.g. 5 hours, 7 days or a calendar month) before it resets.
_Avoid_: cycle, period, interval

**Weekly limit**:
A provider's general limit with a 7-day window. For Claude, it counts use across all models. For Grok, it counts use of Grok Build, the Grok API and other Grok products together.
_Avoid_: weekly quota

**Monthly limit**:
A provider's general limit whose window is the calendar month that ends at its reset time. For Kimi, it counts use of Kimi and Kimi Code together.
_Avoid_: monthly quota, 30-day limit

**Model limit**:
A provider's limit that counts only the use of one particular model. Claude's model limits have 7-day windows; Codex reports the window for each limit.
_Avoid_: model-specific limit, scoped limit

**Utilization**:
The percentage of a limit used in the current window.
_Avoid_: usage, consumption

**Reset time**:
The moment the current window ends and the utilization drops back to zero.
_Avoid_: expiry, renewal, reset date

**Exhausted**:
A limit whose utilization has reached 100 %. Whether further use is available depends on the provider and any separate credit balance.
_Avoid_: used up, full, maxed out

**Menu bar limit**:
The single limit, from any provider, whose utilization the menu bar item shows independently of the open tab. Initially it is the first available limit of the first enabled provider, for Claude the session limit. The user can choose a different limit.
_Avoid_: headline limit, main limit, primary limit

**Overview**:
A shared view of enabled providers, with one entry per provider showing its weekly limit, or its monthly limit when it reports no weekly one. Model limits belong to the individual provider tabs.
_Avoid_: dashboard, summary

### Claude's limits

**Session limit**:
Claude's limit with a 5-hour window ("Current session" in Claude). Its window starts with the first message, so between windows there is none.
_Avoid_: hourly limit, 5h limit

**Fable limit**:
The model limit for Fable, currently the only one.
_Avoid_: Fable usage, Fable quota

## Pace

**Pace**:
The utilization you would have now if you used a limit evenly across its whole window, i.e. the share of the window already elapsed. It rises linearly, day and night.
_Avoid_: target, expected usage

**Pace marker**:
The tick on a limit's bar that shows the pace.
_Avoid_: target line, marker

**Over pace**:
The utilization is above the pace, by at least 1 % when rounded: at the same rate the limit will be exhausted before its reset time.
_Avoid_: ahead, too fast

**Under pace**:
The utilization is below the pace, by at least 1 % when rounded: there is headroom left until the reset time.
_Avoid_: behind, buffer, reserve

**On pace**:
The utilization equals the pace when rounded to whole percent.
_Avoid_: on track, in sync
