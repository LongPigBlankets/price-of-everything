"""Powell with bounds, keeping the best point ever evaluated (scipy's bounded Powell can end a round on a
worse point than it started from)."""
import numpy as np
from scipy import optimize

def best_powell(f, x0, lo, hi, rounds=3, log=print, **opts):
    best = [np.inf, np.clip(np.asarray(x0, float), lo, hi)]
    def g(x):
        x = np.clip(x, lo, hi); v = f(x)
        if v < best[0]:
            best[0], best[1] = v, x.copy()
        return v
    g(best[1])
    for r in range(rounds):
        optimize.minimize(g, best[1], method='Powell', bounds=list(zip(lo, hi)), options=dict(dict(xtol=1e-4, ftol=1e-6), **opts))
        log('round %d best %.4f' % (r, -best[0]))
    return best[1], best[0]
