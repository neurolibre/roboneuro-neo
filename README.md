# Buffy

A service to provide a bot helping scientific journals manage submission reviews.

Buffy automates common editorial tasks like those needed by [The Journal of Open Source Software](https://joss.theoj.org/) or [rOpenSci](https://ropensci.org/).

[![Build Status](https://github.com/openjournals/buffy/actions/workflows/tests.yml/badge.svg)](https://github.com/openjournals/buffy/actions/workflows/tests.yml)
[![Documentation Status](https://readthedocs.org/projects/buffy/badge/?version=latest)](https://buffy.readthedocs.io/en/latest/?badge=latest)

---

## COAR Notify Support

This roboneuro instance includes support for the **COAR Notify protocol**, enabling integration with external peer review and endorsement services like PREreview, PCI Express, and Sciety.

### Features

- Send review requests to external services via bot commands
- Receive and process review/endorsement notifications
- Automatic posting of results to GitHub issues
- W3C Linked Data Notifications (LDN) compliant
- Full notification history and audit trail

### Quick Start

**Enable COAR Notify:**
```bash
export COAR_NOTIFY_ENABLED=true
export DATABASE_URL=postgres://localhost/roboneuro_dev
export COAR_OUTBOX_SECRET=...        # required to send notifications
export COAR_DASHBOARD_USER=...       # required to view the dashboard
export COAR_DASHBOARD_PASSWORD=...
```

**Bot Commands:**
```
@roboneuro coar request from prereview  # Request review from PREreview
@roboneuro coar status                  # Check notification status
@roboneuro coar list                    # List available services
```

These come from the `neurolibre_coar` responder, declared in
`config/settings-<env>.yml` and restricted to editors.

### Documentation

See [app/coar_notify/README.md](app/coar_notify/README.md) for complete documentation including:
- Installation and configuration
- Service setup
- API endpoints
- Security considerations
- Troubleshooting


**Learn more about COAR Notify:** https://coar-notify.net

---
