CREATE OR REPLACE VIEW "${var_glue_table}_athena_view" AS
SELECT
  -- 1/1 Extract specific tag values from the Tags column.
  TRY(REGEXP_EXTRACT(tags, '"Environment": "([^"]*)"', 1)) AS "tag_Environment",
  TRY(REGEXP_EXTRACT(tags, '"CostCenter": "([^"]*)"', 1)) AS "tag_CostCenter",
  TRY(REGEXP_EXTRACT(tags, '"System": "([^"]*)"', 1)) AS "tag_System",
  TRY(REGEXP_EXTRACT(tags, '"Department": "([^"]*)"', 1)) AS "tag_Department",
  -- Tag extraction section END
  *
FROM "${var_glue_table}"
WHERE month >= DATE(to_iso8601(current_date - interval '6' month));