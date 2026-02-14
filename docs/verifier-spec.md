# Final pairing equation
$$ 
e([LHS]_1 +[AUX]_1, [1]_2)
e([U]_1,[\alpha]_2)
e([V]_1,[\alpha^2]_2)
e([W]_1,[\alpha^3]_2)
e([B]_1,[\alpha^4]_2)
=
e([O_{pub}]_1,[\gamma]_2)
e([O_{mid}]_1,[\eta]_2)
e([O_{prv}]_1,[\delta]_2)
e(\kappa_2[\Pi_\chi]_1+\kappa_2^2[M_\chi]_1+\kappa_2^3[N_\chi],[x]_2)
e(\kappa_2[Pi_\zeta]_1+\kappa_2^2[M_\zeta]_1+\kappa_2^3[N_\zeta],[y]_2),
$$

where

$$
[LHS]_1 := [LHS_B]_1 + \kappa_2([LHS_A]_1 + [LHS_C]_1),\\
[LHS_A]_1 := V_{x,y}[U]_1 - [W]_1 + \kappa_1[V]_1 - \kappa_1V_{x,y}[1]_1 - t_n(\chi)[Q_{A,X}]_1 - t_{s_max}(\zeta)[Q_{A,Y}]_1, \\
[LHS_C]_1 := \kappa_1^2((R_{x,y}-1)[K_{-1}(x)L_{-1}(y)]_1+\kappa_0(\chi-1)(R_{x,y}[G]_1-R'_{x,y}[F]_1)+\kappa_0^2K_0(\chi)(R_{x,y}[G]_1-R''_{x,y}[F]_1)-t_{m_l}(\chi)[Q_{C,X}]_1-t_{s_{max}}(\zeta)[Q_{C,Y}]_1)+\kappa_1^3([R]_1-R_{x,y}[1]_1) + \kappa_2([R]_1-R'_{x,y}[1]_1)+ \kappa_2^2([R]_1-R''_{x,y}[1]_1),\\
[LHS_B]_1 := [A_{fix}]_1 + (1+\kappa_2\kappa_1^4)[A_{free}]_1-\kappa_2\kappa_1^4A_{eval}[1]_1,\\
[AUX]_1 := \kappa_2\chi[\Pi_\chi]_1 + \kappa_2\zeta[\Pi_{\zeta}]_1 + \kappa_2^2\omega_{m_I}^{-1}\chi[M_\chi]_1 + \kappa_2^2\zeta[M_\zeta]_1+ \kappa_2^3 \omega_{m_I}^{-1} \chi [N_{\chi}]_1 + \kappa_2^3 \omega_{s_{max}}^{-1} \zeta [N_{\zeta}].
[F]_1 := [B]_1 + \theta_0[s^{(0)}]_1+\theta_1[s^{(1)}]_1+\theta_2[1]_1,\\
[G]_1:= [B]_1+\theta_0[x]_1+\theta_1[y]_1+\theta_2[1]_1.
$$

# Summary of coefficients and group elements in $[LHS]_1 + [AUX]_1$

Grouped by point element (minimal-row form):

$$
[LHS]_1 + [AUX]_1 = \sum_i c_i [P_i]_1
$$

with
$$
C_G := \kappa_2\kappa_1^2 R_{x,y}\big(\kappa_0(\chi-1)+\kappa_0^2K_0(\chi)\big), \quad
C_F := -\kappa_2\kappa_1^2\big(\kappa_0(\chi-1)R'_{x,y}+\kappa_0^2K_0(\chi)R''_{x,y}\big).
$$

| Term | Coefficient $c_i$ | Point element $[P_i]_1$ |
|---|---|---|
| 1 | $1+\kappa_2\kappa_1^4$ | $[A]_1$ |
| 2 | $\kappa_2 V_{x,y}$ | $[U]_1$ |
| 3 | $-\kappa_2$ | $[W]_1$ |
| 4 | $\kappa_2\kappa_1$ | $[V]_1$ |
| 5 | $-\kappa_2 t_n(\chi)$ | $[Q_{A,X}]_1$ |
| 6 | $-\kappa_2 t_{s_{max}}(\zeta)$ | $[Q_{A,Y}]_1$ |
| 7 | $\kappa_2\kappa_1^2(R_{x,y}-1)$ | $[K_{-1}(x)L_{-1}(y)]_1$ |
| 8 | $C_G + C_F$ | $[B]_1$ |
| 9 | $\theta_0 C_F$ | $[s^{(0)}]_1$ |
| 10 | $\theta_1 C_F$ | $[s^{(1)}]_1$ |
| 11 | $\theta_0 C_G$ | $[x]_1$ |
| 12 | $\theta_1 C_G$ | $[y]_1$ |
| 13 | $-\kappa_2\kappa_1^2 t_{m_l}(\chi)$ | $[Q_{C,X}]_1$ |
| 14 | $-\kappa_2\kappa_1^2 t_{s_{max}}(\zeta)$ | $[Q_{C,Y}]_1$ |
| 15 | $\kappa_2\kappa_1^3+\kappa_2^2+\kappa_2^3$ | $[R]_1$ |
| 16 | $-\kappa_2\kappa_1^4A_{pub}-\kappa_2\kappa_1V_{x,y}-\kappa_2\kappa_1^3R_{x,y}-\kappa_2^2R'_{x,y}-\kappa_2^3R''_{x,y}+\theta_2(C_G+C_F)$ | $[1]_1$ |
| 17 | $\kappa_2\chi$ | $[\Pi_\chi]_1$ |
| 18 | $\kappa_2\zeta$ | $[\Pi_\zeta]_1$ |
| 19 | $\kappa_2^2\omega_{m_I}^{-1}\chi$ | $[M_\chi]_1$ |
| 20 | $\kappa_2^2\zeta$ | $[M_\zeta]_1$ |
| 21 | $\kappa_2^3\omega_{m_I}^{-1}\chi$ | $[N_\chi]_1$ |
| 22 | $\kappa_2^3\omega_{s_{max}}^{-1}\zeta$ | $[N_\zeta]_1$ |
