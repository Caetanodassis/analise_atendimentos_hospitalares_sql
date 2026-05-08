# 🏥 Análise de Atendimentos Hospitalares
> Documentação da análise SQL realizada sobre o dataset **Hospital Patient Records**

---

## 📋 Sobre o Dataset

O projeto utiliza **5 tabelas** combinadas para uma análise completa dos atendimentos, custos e comportamento dos pacientes.

> 🔗 Fonte: [Maven Analytics — Hospital Patient Records](https://mavenanalytics.io/data-playground/hospital-patient-records)

| Tabela | Registros | Descrição |
|---|---|---|
| `encounters` | 27.891 | Cada linha é um atendimento hospitalar |
| `patients` | 974 | Dados cadastrais dos pacientes |
| `payers` | 10 | Operadoras de saúde / convênios |
| `procedures` | 47.701 | Procedimentos realizados por atendimento |
| `organizations` | 1 | Dados da organização hospitalar |

### Principais colunas da tabela `encounters`

| Coluna | Tipo | Descrição |
|---|---|---|
| `Id` | Texto | Identificador único do atendimento |
| `START` | DateTime | Data e hora de início |
| `STOP` | DateTime | Data e hora de encerramento |
| `PATIENT` | Texto | ID do paciente (FK → patients) |
| `PAYER` | Texto | ID da operadora (FK → payers) |
| `ENCOUNTERCLASS` | Texto | Tipo: ambulatory, outpatient, wellness, urgentcare, emergency, inpatient |
| `BASE_ENCOUNTER_COST` | Real | Custo base do atendimento |
| `TOTAL_CLAIM_COST` | Real | Custo total cobrado |
| `PAYER_COVERAGE` | Real | Valor coberto pelo convênio |

---

## 🎯 Objetivos da Análise

| # | Objetivo |
|---|---|
| 1 | **Visão Geral dos Atendimentos** — volume, tipos e duração |
| 2 | **Custos e Cobertura** — cobertura zero, procedimentos caros e custo por convênio |
| 3 | **Comportamento dos Pacientes** — sazonalidade, readmissões e casos críticos |

---

# 🔵 Objetivo 1 — Visão Geral dos Atendimentos

---

### 1a. Quantos atendimentos ocorreram em cada ano?

```sql
SELECT
    STRFTIME('%Y', START) AS ANO,
    COUNT(*) AS TOTAL_POR_ANO
FROM
    encounters
GROUP BY
    STRFTIME('%Y', START);
```

**O que faz:** Extrai o ano de cada atendimento e agrupa o total por ano.

**Funções usadas:**
- `STRFTIME('%Y', START)` — função nativa do SQLite que formata uma data. O `%Y` extrai apenas os 4 dígitos do ano. Em PostgreSQL seria `EXTRACT(YEAR FROM START)`, no SQL Server seria `YEAR(START)`
- `GROUP BY` com expressão — no SQLite e PostgreSQL, é permitido referenciar a expressão do `SELECT` diretamente no `GROUP BY`. No SQL Server seria necessário repetir o cálculo ou usar uma subquery

**Resultado:**

| ANO | TOTAL_POR_ANO |
|---|---|
| 2011 | 1.336 |
| 2012 | 2.106 |
| 2013 | 2.495 |
| 2014 | 3.885 |
| 2015 | 2.469 |
| 2016 | 2.451 |
| 2017 | 2.360 |
| 2018 | 2.292 |
| 2019 | 2.228 |
| 2020 | 2.519 |
| 2021 | 3.530 |
| 2022 | 220 |

> 📌 O pico de atendimentos ocorreu em **2014** (3.885) e **2021** (3.530). O ano de 2022 apresenta apenas 220 registros, indicando que o dataset foi encerrado no início daquele ano.

---

### 1b. Porcentagem por tipo de atendimento por ano — dois caminhos

Este é o ponto central do Objetivo 1 e demonstra duas formas de resolver o mesmo problema: uma clássica (CTE + JOIN) e uma moderna **(Window Function)**.

#### O problema

Precisamos saber, dentro de cada ano, qual a fatia que cada tipo de atendimento representa. Para calcular uma porcentagem, precisamos do **detalhe** (contagem por tipo) e do **total** (soma do ano) ao mesmo tempo, na mesma linha. Com um `GROUP BY` simples, só conseguimos uma granularidade por vez.

---

#### Caminho 1 — CTE + JOIN

```sql
WITH TOTAL_ANO AS (
    SELECT
        STRFTIME('%Y', START) AS ANO,
        COUNT(*) AS TOTAL_POR_ANO
    FROM
        encounters
    GROUP BY
        STRFTIME('%Y', START)
)
SELECT
    STRFTIME('%Y', START) AS ANO,
    ENCOUNTERCLASS,
    COUNT(*) AS QUANTIDADE_DE_ATENDIMENTO,
    T1.TOTAL_POR_ANO,
    1.0 * COUNT(*) / T1.TOTAL_POR_ANO AS PORCENTAGEM
FROM
    encounters AS T0
JOIN
    TOTAL_ANO AS T1 ON STRFTIME('%Y', START) = T1.ANO
GROUP BY
    ANO, ENCOUNTERCLASS
ORDER BY
    ANO, PORCENTAGEM DESC;
```

**Como funciona:**
1. A CTE `TOTAL_ANO` calcula o total de atendimentos por ano
2. O `JOIN` traz esse total para cada linha da query principal
3. A divisão calcula a porcentagem por tipo dentro do ano

**Por que o `1.0 *`?** `COUNT(*)` e `TOTAL_POR_ANO` são inteiros. Divisão entre dois inteiros em SQL sempre resulta em inteiro arredondado — como o numerador é sempre menor que o denominador, o resultado seria `0` para todos os casos. Multiplicar por `1.0` antes força a operação para ponto flutuante, preservando os decimais.

---

#### Caminho 2 — Window Function `OVER` ⭐

```sql
SELECT
    STRFTIME('%Y', START) AS ANO,
    ENCOUNTERCLASS,
    COUNT(*) AS QUANTIDADE_DE_ATENDIMENTO,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY STRFTIME('%Y', START)),
        2
    ) AS PORCENTAGEM
FROM
    encounters
GROUP BY
    ANO, ENCOUNTERCLASS
ORDER BY
    ANO, PORCENTAGEM DESC;
```

**Como funciona:** Uma única query resolve tudo — sem CTE, sem JOIN.

---

## 🪟 Window Functions — Entendendo o `OVER`

> Window Functions são uma das ferramentas mais poderosas do SQL moderno. Diferente do `GROUP BY`, elas calculam valores sobre um conjunto de linhas **sem colapsar o resultado** — o detalhe de cada linha é preservado enquanto o valor agregado aparece ao lado.

### A anatomia do `OVER`

```sql
SUM(COUNT(*)) OVER (PARTITION BY STRFTIME('%Y', START))
-- ──────────── ────────────────────────────────────────
-- Função de    A "janela": define o grupo sobre o qual
-- agregação    a função será calculada
```

### `PARTITION BY` — o coração da janela

`PARTITION BY` divide os dados em grupos (partições) — similar ao `GROUP BY`. A diferença fundamental: enquanto o `GROUP BY` retorna **uma linha por grupo**, o `PARTITION BY` **replica o resultado de volta para cada linha dentro do grupo**.

**Visualizando o comportamento para 2011:**

| ANO | ENCOUNTERCLASS | COUNT(*) | SUM(COUNT(*)) OVER (PARTITION BY ANO) |
|---|---|---|---|
| 2011 | ambulatory | 667 | **1.336** |
| 2011 | outpatient | 327 | **1.336** |
| 2011 | wellness | 174 | **1.336** |
| 2011 | inpatient | 83 | **1.336** |
| 2011 | emergency | 55 | **1.336** |
| 2011 | urgentcare | 30 | **1.336** |
| 2012 | ambulatory | 895 | **2.106** |
| 2012 | outpatient | 444 | **2.106** |

> O total `1.336` é calculado uma vez para o ano 2011, mas aparece em **todas as linhas de 2011** — sem JOIN, sem subquery.

### Comparando as duas abordagens

| | CTE + JOIN | Window Function (`OVER`) |
|---|---|---|
| **Linhas de código** | ~15 linhas | ~8 linhas |
| **Legibilidade** | Verbosa, mas explícita | Compacta |
| **Performance** | Dois passes na tabela | Um único passe |
| **Compatibilidade** | Universal | SQLite 3.25+, PostgreSQL, SQL Server 2005+ |
| **Quando usar** | CTE reutilizada em vários lugares | Cálculo isolado, código mais limpo |

---

**Resultado (todos os anos):**

| ANO | ENCOUNTERCLASS | QUANTIDADE | PORCENTAGEM |
|---|---|---|---|
| 2011 | ambulatory | 667 | 49.93% |
| 2011 | outpatient | 327 | 24.48% |
| 2011 | wellness | 174 | 13.02% |
| 2011 | inpatient | 83 | 6.21% |
| 2011 | emergency | 55 | 4.12% |
| 2011 | urgentcare | 30 | 2.25% |
| 2012 | ambulatory | 895 | 42.50% |
| 2012 | outpatient | 444 | 21.08% |
| 2012 | urgentcare | 299 | 14.20% |
| 2012 | wellness | 192 | 9.12% |
| 2012 | emergency | 183 | 8.69% |
| 2012 | inpatient | 93 | 4.42% |
| 2013 | ambulatory | 1.106 | 44.33% |
| 2013 | outpatient | 485 | 19.44% |
| 2013 | urgentcare | 359 | 14.39% |
| 2013 | emergency | 225 | 9.02% |
| 2013 | wellness | 186 | 7.45% |
| 2013 | inpatient | 134 | 5.37% |
| 2014 | ambulatory | 2.341 | 60.26% |
| 2014 | outpatient | 694 | 17.86% |
| 2014 | urgentcare | 327 | 8.42% |
| 2014 | emergency | 216 | 5.56% |
| 2014 | wellness | 189 | 4.86% |
| 2014 | inpatient | 118 | 3.04% |
| 2015 | ambulatory | 1.073 | 43.46% |
| 2015 | outpatient | 506 | 20.49% |
| 2015 | urgentcare | 380 | 15.39% |
| 2015 | emergency | 228 | 9.23% |
| 2015 | wellness | 171 | 6.93% |
| 2015 | inpatient | 111 | 4.50% |
| 2016 | ambulatory | 1.073 | 43.78% |
| 2016 | outpatient | 481 | 19.62% |
| 2016 | urgentcare | 341 | 13.91% |
| 2016 | emergency | 250 | 10.20% |
| 2016 | wellness | 182 | 7.43% |
| 2016 | inpatient | 124 | 5.06% |
| 2017 | ambulatory | 987 | 41.82% |
| 2017 | outpatient | 475 | 20.13% |
| 2017 | urgentcare | 385 | 16.31% |
| 2017 | emergency | 218 | 9.24% |
| 2017 | wellness | 169 | 7.16% |
| 2017 | inpatient | 126 | 5.34% |
| 2018 | ambulatory | 933 | 40.71% |
| 2018 | outpatient | 480 | 20.94% |
| 2018 | urgentcare | 377 | 16.45% |
| 2018 | emergency | 247 | 10.78% |
| 2018 | wellness | 174 | 7.59% |
| 2018 | inpatient | 81 | 3.53% |
| 2019 | ambulatory | 846 | 37.97% |
| 2019 | outpatient | 456 | 20.47% |
| 2019 | urgentcare | 397 | 17.82% |
| 2019 | emergency | 227 | 10.19% |
| 2019 | wellness | 168 | 7.54% |
| 2019 | inpatient | 134 | 6.01% |
| 2020 | ambulatory | 1.192 | 47.32% |
| 2020 | outpatient | 497 | 19.73% |
| 2020 | urgentcare | 365 | 14.49% |
| 2020 | emergency | 234 | 9.29% |
| 2020 | wellness | 159 | 6.31% |
| 2020 | inpatient | 72 | 2.86% |
| 2021 | outpatient | 1.418 | 40.17% |
| 2021 | ambulatory | 1.303 | 36.91% |
| 2021 | urgentcare | 378 | 10.71% |
| 2021 | emergency | 221 | 6.26% |
| 2021 | wellness | 155 | 4.39% |
| 2021 | inpatient | 55 | 1.56% |
| 2022 | ambulatory | 121 | 55.00% |
| 2022 | outpatient | 37 | 16.82% |
| 2022 | urgentcare | 28 | 12.73% |
| 2022 | emergency | 18 | 8.18% |
| 2022 | wellness | 12 | 5.45% |
| 2022 | inpatient | 4 | 1.82% |

> 📌 **Ambulatory** é consistentemente o tipo mais frequente, oscilando entre 37% e 60% dos atendimentos em quase todos os anos. **Inpatient** (internação) é sempre o menos frequente (1–6%), mas concentra os maiores custos. Em 2021, **Outpatient** ultrapassou Ambulatory pela única vez no histórico.

---

### 1c. Porcentagem de atendimentos por duração (mais ou menos de 24h)

```sql
SELECT
    categoria,
    COUNT(*) AS QUANTIDADE_DE_ATENDIMENTO,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    ) AS PORCENTAGEM
FROM (
    SELECT
        CASE
            WHEN (julianday(STOP) - julianday(START)) * 24 > 24 THEN 'Mais de 24h'
            ELSE 'Menos de 24h'
        END AS categoria
    FROM
        encounters
)
GROUP BY
    categoria;
```

**O que faz:** Classifica cada atendimento por duração e calcula a porcentagem de cada categoria sobre o total geral.

**Funções e conceitos usados:**

**`julianday()` — calculando duração em horas:**
```sql
(julianday(STOP) - julianday(START)) * 24
```
`julianday()` converte qualquer data para um número decimal de dias (ex: `2.5` = 2 dias e 12 horas). A subtração resulta na duração em dias — multiplicar por `24` converte para horas.

**`CASE WHEN` dentro de Subquery:**
A classificação é feita na query interna, que cria a coluna `categoria`. A query externa apenas agrupa e conta — separando responsabilidades e facilitando a leitura.

**`OVER ()` sem `PARTITION BY` — janela global:**
```sql
SUM(COUNT(*)) OVER ()
```
Quando o `OVER` vem **vazio**, a janela engloba **todas as linhas do resultado** sem nenhuma subdivisão. Aqui queremos a porcentagem sobre o total absoluto — diferente da query anterior, onde a janela era particionada por ano.

| Sintaxe | Comportamento |
|---|---|
| `OVER (PARTITION BY ANO)` | Total calculado dentro de cada ano |
| `OVER ()` | Total calculado sobre todas as linhas |

**Resultado:**

| CATEGORIA | QUANTIDADE | PORCENTAGEM |
|---|---|---|
| Menos de 24h | 27.816 | 99.73% |
| Mais de 24h | 75 | 0.27% |

> 📌 Apenas **75 atendimentos** (0,27%) duraram mais de 24 horas. Isso confirma o que vimos na query anterior: **Inpatient** é raro em número, mas altamente significativo em custo e complexidade clínica.

---

*Análise realizada com SQLite sobre o dataset **Hospital Patient Records** — 27.891 atendimentos, 974 pacientes, 47.701 procedimentos (2011–2022).*
*Fonte: [Maven Analytics Data Playground](https://mavenanalytics.io/data-playground/hospital-patient-records)*
