#!/usr/bin/env bash
# A small research house: a scout that reads papers (and may reach nothing but
# arXiv and its model), a quantum specialist, a builder that turns decisions
# into code, and a weaver for prototyping multi-agent designs. Run it once,
# then `agentdorm up`.
#
#   AGENTDORM_HOME=~/dorms/research examples/research-house.sh
set -euo pipefail
ad="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/agentdorm"

"$ad" new scout --agent hermes --egress allowlist --allow arxiv.org,export.arxiv.org \
  --description "Research scout for quantum computing and AI agents. Finds new arXiv papers,
reads them properly, and writes short, sourced summaries. Flags claims that look
too good. Hands implementation questions to builder and quantum questions to quantum."

"$ad" new quantum --agent hermes \
  --description "Quantum computing engineer: Qiskit circuits, transpilation, noise models
and error mitigation. Verifies every claim by running code, and says which
results only hold on simulators."

"$ad" new builder --agent nanoloop \
  --description "Backend engineering end to end: Python services, tests and CI. Takes a
task from any housemate, ships the smallest correct change, and reports what
it changed and how it was verified."

"$ad" new weaver --agent loomloop \
  --description "Runs LoomLoop multi-agent systems sent to it and reports how they behaved."

echo
"$ad" ls
echo
echo "Start them with: agentdorm up    (then: agentdorm ps, agentdorm who)"
