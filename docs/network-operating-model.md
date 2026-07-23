# Network operating model

> **Status:** adopted for the current hardware layout after a read-only check on
> 2026-07-23 (grimnir#12). This is an operating contract, not a request to
> reconfigure either host.

## Purpose

The NAS was deliberately moved to a location where it connects over Wi-Fi. A
disconnected Ethernet cable on that host is therefore expected, rather than an
incident. The control Pi is deliberately dual-homed while services and
maintenance continue to run. This document prevents a well-meaning repair from
turning an intentional layout into an outage.

## Current transport policy

| Node | LAN role | Cross-node service/observability role |
|---|---|---|
| NAS | **NAS Wi-Fi is the current intentional primary LAN path.** Ethernet may be physically disconnected and must not be treated as a failed service. | Use the control host's stable Tailscale identity from the owner-only runtime overlay for service-to-service traffic and Heimdall telemetry. |
| Control Pi (`huginmunin`) | Both Ethernet and Wi-Fi may be up; the **control host's Ethernet remains the preferred default route**. Wi-Fi is retained as a live resilience path. | Accept NAS-originated traffic on the Tailscale identity, rather than assuming one particular LAN address is reachable. |

**Tailscale is the required transport for NAS-to-control observability.** In
particular, producers on the NAS must target the stable Tailscale identity
provided by the owner-only runtime overlay: either its MagicDNS name or Tailnet
address, not a `.local` name or hard-coded LAN address. The service owner is
responsible for its endpoint configuration; Grimnir records the cross-component
transport rule without publishing the private locator.

This policy does not require Mimir itself to listen on the LAN. Its local
loopback listener and its separately configured ingress are deliberate service
boundaries, not proof that NAS Wi-Fi is unhealthy.

## Safe verification

These checks are read-only and intentionally distinguish transport from service
health:

1. On the NAS, inspect `ip -br addr`, `ip route show default`, and
   `tailscale status --self`. A carrier-less NAS `eth0`, an active `wlan0`, and
   an active Tailscale address match the intended layout.
2. On the NAS, check the local service boundary with
   `curl -fsS http://127.0.0.1:3031/health`; this proves Mimir's listener is
   healthy without assuming it should bind to Wi-Fi.
3. From the NAS, check the control-plane health through Tailscale, for example
   `curl -fsS http://<control-tailnet-host>:3033/health`, substituting the
   owner-only MagicDNS name or Tailnet address. An HTTP response proves the
   transport path even if a protected endpoint later requires credentials.
4. On the control Pi, inspect both routes and confirm the Ethernet default has
   the preferred metric. Check the declared Grimnir timers independently of
   interface state.

If the Tailscale probe fails while the local Mimir probe passes, investigate the
telemetry endpoint, name resolution, and tailnet state first. Do not change
NAS Wi-Fi or Mimir's bind address as a first response.

## Change boundary

Network routing is substrate work owned by Brokkr; service endpoint changes are
owned by the affected service repository. A Grimnir runbook may coordinate the
contract, but it must not silently mutate live interfaces.

Do not disable, reprioritize, or restart either host's network interfaces
outside an approved maintenance window with a reachable-console and rollback
plan. Before such a window, record the existing addresses, default routes,
Tailscale state, and the verification commands above. Afterward, prove both
local Mimir health and NAS-to-control Tailscale reachability before declaring
the change complete.
