# Roadmap

[Português](ROADMAP.md) · **English** · [Español (Honduras)](ROADMAP.es-HN.md)

This document shows where the project may go and what we have learned so far. Nothing below is a promise of a date: these are intentions, in rough order of priority. Suggestions are welcome through an *issue*.

## Short term

**Dashboard**

- **Protect or remove the diagnostics endpoint.** `api_ativos.php?debug=1` shows the GLPI field structure and does not require authentication. Restrict it by IP at the web server, or disable it in production.
- **Take the SSD list out of the HTML.** Today `SSD_EXPANSION_LIST` is a list of hostnames inside the page. Move it to a configuration file and, even better, read the storage type (HDD/SSD) straight from the GLPI inventory.
- **Configurable classification rules.** The RAM threshold, the CPU generations considered "OK/Attention/Obsolete" and the server types in a configuration file, instead of constants in the code.
- **Demo mode.** A set of fictitious data to try the dashboard without a GLPI instance and to produce the README screenshots.
- **Automated tests** for the CPU classification, the RAM alert and the normalization of the "Owner" field, using sample data.
- **Restrict the API client by IP** in GLPI, leaving only the dashboard server authorized.
- **Tune `cache_ttl_seconds`** according to real usage (today 15 minutes).

**Data quality in GLPI** (the dashboard only shows what is registered; the fix belongs at the source)

- Fill in the Status and Type of monitors, which arrive empty.
- Register the phones (the code already handles the empty list without errors).
- Make the Group field mandatory in the registration form.
- Use a structured asset tag number instead of free text in the comments.
- Record the purchase date and warranty in the financial tab.
- Set up a periodic routine to audit duplicated hostnames and assets with no owner.

**Agent GPO**

- **Parameterize the scripts.** Target version, server and network folder in a configuration file next to the script, instead of editing the code at every update.
- **Monitor the logs** after each rollout and investigate agents that go days without contact or are still on old versions.
- **Re-confirm the tray icon** with every new agent version, using the manual test described in [`docs/gpo-glpi-agent.md`](docs/gpo-glpi-agent.md), before going to production.
- **Clean up legacy scripts** that are no longer used from the network folder.
- **Document which account** has write permission on the share, so updates do not run into the permission block.

## Long term

- **Optional per-department authentication**, integrated with the directory (LDAP/Active Directory) instead of local passwords: each manager sees only their own area, and IT sees everything. A first version with local passwords was built and later dropped for simplicity.
- **Direct budget support.** Export the filtered view (CSV/Excel), project how many devices need replacing per year and per department, and estimate costs.
- **Classification beyond the CPU:** equipment age, warranty and storage type.
- **History and trends.** Keep periodic snapshots of the fleet to show its evolution (for example, the percentage of obsolete equipment over time).
- **Alerts** for IT when an obsolete asset, a duplicated hostname or an agent with no contact for several days shows up.
- **More asset types:** printers, network equipment and other GLPI itemtypes.
- **Multi-language interface.** Today the main documentation is trilingual, but the dashboard texts are in Portuguese. Move the texts to a language file.
- **Packaging** as a container, for faster installation and demos.
- **Alternatives to GPO** for deploying the agent (for example, endpoint managers) and support for non-Windows workstations.
- **Translate the `docs/` folder** into English and Honduran Spanish.

## Lessons learned

1. **Validate the first real data, not just the absence of errors.** GLPI stores memory in MB and the dashboard rule expected GB. Nothing failed: every device would simply have looked like it "needs no RAM upgrade". Only checking the first real response revealed the problem.
2. **GLPI fields vary between installations.** The search uids are compound (`Computer.<Type>.<field>`) and differ from what the documentation suggests. Discovering the fields dynamically and having a diagnostics mode (`?debug=1`) saved a lot of time.
3. **Understand the root cause, not just the symptom.** The agent's tray icon did not show up when installed by GPO. Reading the internal tables of the `.msi` showed that the component is only installed on a fresh install with `AGENTMONITOR=1` **and** `EXECMODE=1`; repairing or reinstalling features does not fix it, but a major-version *upgrade* does.
4. **Not every "bug" is a bug.** The icon that "disappeared" hours after installing was just an autostart that had not fired yet, because a new session was missing. Checking that first avoids unnecessary investigation.
5. **Be idempotent and polite to the server.** A lock (mutex), a random delay before acting and a minimum interval between inventories prevented duplicate installs and a flood of machines hitting GLPI at the same time.
6. **Make sure errors show up.** In the scripts, using `-ErrorAction Stop` inside `try/catch` makes an "access denied" error land in the log instead of vanishing silently when the script runs with nobody watching.
7. **Never change production to test.** The dashboard got its own directory and vhost; the GLPI vhost was never touched. Always `nginx -t` before `reload` (never `restart`), and a pilot with an isolated GPO before the full rollout.
8. **File permissions are a constant source of errors.** A file copied as root after the `chown` goes back to `root:root` and PHP-FPM cannot read it (HTTP 500). Reapply owner and permissions after every upload.
9. **Check that the update really arrived.** A `grep` for a snippet exclusive to the new version, plus the file size, catches the upload that did not overwrite or the old copy sent by mistake.
10. **A valid certificate does not require opening to the internet.** Putting the dashboard behind a reverse proxy that only serves private addresses gave warning-free HTTPS without exposing data, which matters because the dashboard has no login.
11. **The dashboard shows the problems, but the fix belongs at the source.** Duplicated hostnames, empty groups and assets with no owner appear in the quality indicators, and only fixing the record in GLPI really solves them.
12. **Scope changes are part of the job.** The per-department login was built and then cancelled at management's request. Keeping it behind a configuration switch made the change cheap, and the dead code was later removed from the published package.
13. **Document as you go.** The records of decisions, bugs and tests are what made it possible to resume the work and, now, to publish it.
