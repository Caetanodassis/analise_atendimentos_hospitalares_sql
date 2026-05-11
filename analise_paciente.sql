
-- OBJETIVO 1: VISÃO GERAL DOS ATENDIMENTOS (ENCOUNTERS)

-- a. Quantos atendimentos (encounters) totais ocorreram em cada ano?

-- 1) Ver a tabela encounters 
SELECT * FROM encounters;

--2) Contar quantos atendimento (cada linha é um atendimento)
SELECT  
	COUNT(*) AS QUANTIDADE_DE_ATENDIMENTO
FROM 
	encounters
;	

-- b. Para cada ano, qual a porcentagem de todos os atendimentos que pertence a cada tipo de atendimento (ambulatorial, outpatient, wellness, urgência, emergência e internação)?

--explicar o windows fuction
SELECT 
	STRFTIME('%Y',"START") AS ANO,
	COUNT(*) AS TOTAL_POR_ANO
FROM 
	encounters
GROUP BY 
	STRFTIME('%Y',"START") -- SQL SERVER NÃO ACEITARIA SE FOSSE ANO, MAS O POSTGRE E SQLITE SIM, DEVIDO AO FATO DE LER PRIMEIRO O GROUP BY DEPOIS O SELECT

	
--NO CODIGO ACIMA TEM O TOTAL DE TODO ANO, PORÉM VAMOS PRECISAR COLOCAR ESSE
--VALOR DE TODO ANO EM TODAS AS LINHAS EM SEU DEVIDO ANO
--EXEMPLO: TODA LINHA QUE TIVER O ANO DE 2011 VAI TER 1,336 NA COLOCA TOTAL_POR_ANO
--E EXISTE FORMAS DIFERENTES DISSO UMA USANDO CTE E JOIN, E OUTRA USANDO WINDOWS FUCTION (OVER)
	

--usando CTE junto com Join
WITH TOTAL_ANO AS (
SELECT 
	STRFTIME('%Y',"START") AS ANO,
	COUNT(*) AS TOTAL_POR_ANO
FROM 
	encounters
GROUP BY 
	STRFTIME('%Y',"START")
)
SELECT  
	STRFTIME('%Y',"START") AS ANO,
	ENCOUNTERCLASS,
	COUNT(*) AS QUANTIDADE_DE_ATENDIMENTO,
	T1.TOTAL_POR_ANO,
	1. * COUNT(*) / T1.TOTAL_POR_ANO AS PORCENTAGEM -- ESSE 1. É PAR AMULTIPLICAR COM DECIMAL, POIS INTEIRO COM INTEIRO VAI DA SEMPRE ARREDONDADO SENDO QUE OS VALORES SERÃO 0,49925...
FROM 
	Encounters AS T0
JOIN 
	TOTAL_ANO AS T1 ON STRFTIME('%Y',"START") = T1.ANO
GROUP BY
	ANO, ENCOUNTERCLASS
ORDER BY 
	ANO, PORCENTAGEM DESC
;


--usando windows fuction OVER
SELECT  
	STRFTIME('%Y',"START") AS ANO,
	ENCOUNTERCLASS,
	COUNT(*) AS QUANTIDADE_DE_ATENDIMENTO,
	ROUND(
		COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY STRFTIME('%Y', START)),2
	) AS PORCENTAGEM
FROM 
	encounters
GROUP BY
	ANO, ENCOUNTERCLASS
ORDER BY 
	ANO, PORCENTAGEM DESC
;
	
-- c. Qual a porcentagem de atendimentos que duraram mais de 24 horas versus menos de 24 horas?
SELECT 
	categoria,
	COUNT(*) AS QUANTIDADE_DE_ATENDIMENTO,
	ROUND(
		 COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 2
		) AS PORCENTAGEM
FROM(
	SELECT
		CASE
			WHEN (julianday(STOP) - julianday(START)) * 24 > 24 THEN 'Mais de 24h' -- julianday em sqlite volta em dias por isso multiplicar por 24
			ELSE 'Menos de 24h'
		END AS categoria
	FROM
		encounters
)
GROUP BY 
	categoria
;


-- OBJETIVO 2: INSIGHTS DE CUSTO E COBERTURA

-- a. Quantos atendimentos tiveram cobertura zero do convênio (payer), e qual a porcentagem disso em relação ao total de atendimentos?
SELECT 
	COUNT(*) AS QUANTIDADE_DE_COBERTURA_0,
	ROUND(
		COUNT(*) * 100.0 / (SELECT COUNT(*) FROM encounters), 2
	) AS PORCENTAGEM_DE_COBERTURA_0
FROM
	encounters
WHERE
	PAYER_COVERAGE = 0
;

-- b. Quais são os 10 procedimentos mais frequentes realizados e o custo base médio de cada um?
WITH procedimentos AS (
	SELECT
		ENCOUNTERCLASS,
		BASE_ENCOUNTER_COST 
	FROM 
		encounters
)
SELECT 
	RANK() OVER (ORDER BY COUNT(*) DESC) AS RANKING,
	ENCOUNTERCLASS AS PROCEDIMENTOS,
	--COUNT(*) AS QUANTIDADE_PROCEDIMENTO,
	--SUM(BASE_ENCOUNTER_COST) AS CUSTO_DE_PROCEDIMENTO
	ROUND(AVG(BASE_ENCOUNTER_COST),2) AS CUSTO_MEDIO
FROM
	procedimentos
GROUP BY
	ENCOUNTERCLASS
LIMIT 10
;

-- c. Quais são os 10 procedimentos com maior custo base médio e quantas vezes foram realizados?
WITH procedimentos AS (
	SELECT
		ENCOUNTERCLASS,
		BASE_ENCOUNTER_COST 
	FROM 
		encounters
)
SELECT
	RANK() OVER (ORDER BY ROUND(AVG(BASE_ENCOUNTER_COST),2) DESC) AS RANKING,
	ENCOUNTERCLASS AS PROCEDIMENTOS,
	COUNT(*) AS QUANTIDADE_DE_PROCEDIMENTOS
FROM
	procedimentos
GROUP BY
	ENCOUNTERCLASS
LIMIT 10
;

-- d. Qual é o custo médio total das faturas (total claim cost) dos atendimentos, separado por convênio (payer)?
SELECT
    p.NAME AS CONVENIO,
    ROUND(AVG(e.TOTAL_CLAIM_COST), 2) AS CUSTO_TOTAL_MEDIO
FROM 
	encounters e
JOIN 
	payers p
    ON p.Id = e.PAYER
GROUP BY 
	p.NAME
ORDER BY 
	CUSTO_TOTAL_MEDIO DESC
;
	
-- OBJETIVO 3: ANÁLISE DE COMPORTAMENTO DOS PACIENTES

-- a. Quantos pacientes únicos foram admitidos a cada trimestre ao longo do tempo?
SELECT 
	strftime('%Y', START) AS ANOS,
	CAST((strftime('%m', START) - 1) / 3 + 1 AS INTEGER) AS TRIMESTRE,
	COUNT(DISTINCT PATIENT) AS QUANTIDADE_DE_PACIENTE_ADITIDOS
FROM 
	encounters
WHERE 
	ENCOUNTERCLASS = 'inpatient'
GROUP BY
	strftime('%Y', DATETIME(START)), CAST((strftime('%m', DATETIME(START)) - 1) / 3 + 1 AS INTEGER)
ORDER BY
	ANOS, TRIMESTRE
;

-- b. Quantos pacientes foram readmitidos dentro de 30 dias após um atendimento anterior?
WITH internacao AS(
	SELECT 
		e.PATIENT,
		e."START",
		LAG(e."START" ) OVER(PARTITION BY e.PATIENT ORDER BY e."START") AS DATA_ANTERIOR
	FROM 
		encounters e
	WHERE 
		e.ENCOUNTERCLASS = 'inpatient'
)
SELECT 
	COUNT(DISTINCT PATIENT) AS PACIENTE_READMITIDO_30_DIAS
FROM 
	internacao
WHERE 
	DATA_ANTERIOR IS NOT NULL AND (JULIANDAY("START") - JULIANDAY(DATA_ANTERIOR)) <=30
;

-- c. Quais pacientes tiveram o maior número de readmissões?
WITH internacao AS(
	SELECT 
		e.PATIENT,
		e."START",
		LAG(e."START" ) OVER(PARTITION BY e.PATIENT ORDER BY e."START") AS DATA_ANTERIOR
	FROM 
		encounters e
	WHERE 
		e.ENCOUNTERCLASS = 'inpatient'
), contagem AS (
SELECT
	PATIENT,
	COUNT(DISTINCT PATIENT) AS QTD_READMISSOES
FROM 
	internacao
WHERE 
	DATA_ANTERIOR IS NOT NULL AND (JULIANDAY("START") - JULIANDAY(DATA_ANTERIOR)) <=30
GROUP BY 
    PATIENT
)
SELECT 
    Patient,
    QTD_READMISSOES
FROM 
	contagem
WHERE 
	QTD_READMISSOES = (
    	SELECT MAX(QTD_READMISSOES) FROM contagem
)
;

--https://mavenanalytics.io/data-playground/hospital-patient-records
