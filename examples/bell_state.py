"""Bell state (quantum entanglement) demo for the dsh container.

Run inside the harness shell (Python + Qiskit are baked into the image):

    python bell_state.py

Creates |Φ⁺⟩ = (|00⟩ + |11⟩)/√2: a Hadamard puts qubit 0 into
superposition, then a CNOT entangles it with qubit 1. Measuring 1000
shots should give roughly 50/50 '00' and '11' — and never '01'/'10',
which is the entanglement signature.
"""

import matplotlib
matplotlib.use("Agg")  # no display in the container; render to file

from qiskit import QuantumCircuit, transpile
from qiskit_aer import AerSimulator
from qiskit.visualization import plot_histogram


def build_circuit() -> QuantumCircuit:
    qc = QuantumCircuit(2, 2)
    qc.h(0)          # qubit 0: |0> -> superposition
    qc.cx(0, 1)      # CNOT: entangle qubit 1 with qubit 0
    qc.measure([0, 1], [0, 1])
    return qc


def main() -> None:
    qc = build_circuit()
    print(qc.draw())

    sim = AerSimulator()
    counts = sim.run(transpile(qc, sim), shots=1000).result().get_counts()
    print("counts:", counts)

    correlated = counts.get("00", 0) + counts.get("11", 0)
    print(f"correlated outcomes: {correlated}/1000 "
          f"(expected ~1000 for a perfect Bell state)")

    plot_histogram(counts, filename="bell_state_histogram.png")
    print("histogram saved to bell_state_histogram.png")


if __name__ == "__main__":
    main()
