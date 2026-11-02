import numpy as np
import pandas as pd
from scipy import stats
from statsmodels.stats.proportion import proportions_ztest, proportion_confint, proportion_effectsize
from statsmodels.stats.power import NormalIndPower

df = pd.read_csv("ab_users.csv")
print(df.shape)
print(df.head())

# исследуемая метрика - покупка в первые 7 дней после входа в эксперимент
metric = "bought_7d"
alpha = 0.05

control = df[df["group"] == "control"]
test = df[df["group"] == "test"]

# проверка SRM: правильно ли разделились группы
n_c, n_t = len(control), len(test)
chi2, p_srm = stats.chisquare([n_c, n_t])   # ожидаем 50/50
print(f"SRM: control={n_c}, test={n_t}, p-value={p_srm:.4f}")
# Если p-value < alpha, отвергаем H0

# сколько пользователей нужно на группу, чтобы заметить минимальный интересный эффект
p_base = control[metric].mean()
mde_rel = 0.05                      # 5% - прирост конверсии
p_target = p_base * (1 + mde_rel)

effect = proportion_effectsize(p_target, p_base)
n_needed = NormalIndPower().solve_power(effect_size=effect, alpha=alpha, power=0.8, ratio=1.0)
print(f"Базовая конверсия: {p_base:.4f}")
print(f"Нужно на группу: {int(np.ceil(n_needed))}, фактически: control={n_c}, test={n_t}")


# основной тест: z-тест для двух долей
successes = np.array([test[metric].sum(), control[metric].sum()])
nobs = np.array([n_t, n_c])

z_stat, p_value = proportions_ztest(successes, nobs, alternative="two-sided")
conv_c, conv_t = successes[1] / n_c, successes[0] / n_t
print(f"Конверсия control={conv_c:.4%}, test={conv_t:.4%}")
print(f"Абсолютная разница: {conv_t - conv_c:.4%}")
print(f"Относительный прирост: {(conv_t / conv_c - 1):.2%}")
print(f"z={z_stat:.3f}, p-value={p_value:.5f}")
# H0 отвергается, эксперимент показывает положительное влияние тестируемого изменения на конверсию в покупку в первые 7 дней

# доверительный интервал для разницы долей (95%) - оценить диапазон возможных значений эффекта
diff = conv_t - conv_c
se = np.sqrt(conv_t * (1 - conv_t) / n_t + conv_c * (1 - conv_c) / n_c)
z_crit = stats.norm.ppf(1 - alpha / 2)
ci_low, ci_high = diff - z_crit * se, diff + z_crit * se
print(f"95% ДИ для разницы: [{ci_low:.4%}, {ci_high:.4%}]")

# сегменты (платформа, источник трафика)
results = []
for seg in ["platform", "traffic_source"]:
    for value, part in df.groupby(seg):
        c = part[part["group"] == "control"][metric]
        t = part[part["group"] == "test"][metric]
        if len(c) > 0 and len(t) > 0:
            _, p = proportions_ztest([t.sum(), c.sum()], [len(t), len(c)])
            results.append((seg, value, len(c), len(t), c.mean(), t.mean(), p))
seg_df = pd.DataFrame(results, columns=["segment", "value", "n_control", "n_test", "conv_control", "conv_test", "p_value"])
print(seg_df)
