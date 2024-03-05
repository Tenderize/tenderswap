UNIT = 1e18
BASE_FEE = 0.005


def quote(x, u, U, s, S, L, K):
    sumA = ((u + x) * K - U + u) * ((U + x) / L)**K

    sumB = (U - u - K * u) * (U / L)**K

    nom = (sumA + sumB) * (S + U)
    denom = K * (UNIT + K) * (s + u)

    fee = BASE_FEE * x + nom / denom
    out = x - fee
    return (out, fee)
