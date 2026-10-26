# Graphical abstract

The graphical abstract connects the Daniels system and adversarial knowledge to action selection, robustness and VoIR. The result panel uses the corrected Figure 6 curves for $h=1,5,10$. It illustrates how the value of knowledge rises and then falls with attack size in this example. The decline concerns the additional advantage of information over an uninformed attack; it does not mean that larger attacks cause less damage.

- [Vector PDF](voir_graphical_abstract.pdf)
- [PNG image](voir_graphical_abstract.png)
- [Editable drawing source](build_graphical_abstract.py)
- [Plotted coordinates](figure6_selected.csv)

The three known component identities in the left panel illustrate a possible observation. The curves use the selected responses averaged over all possible observations for each plotted knowledge state, before evaluating the divergence.

To redraw the figure, run the following commands from this folder:

```text
python build_graphical_abstract.py
pdftoppm -r 300 -singlefile -png voir_graphical_abstract.pdf voir_graphical_abstract
```

Drawing requires Python 3, ReportLab, and Arial and Times New Roman. The font directory is set near the beginning of the source; adjust it for another installation. PNG export requires Poppler. The saved coordinates are sufficient to redraw the figure without MATLAB or new simulations.
