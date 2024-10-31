CREATE OR REPLACE VIEW "${var_glue_table}_athena_view" AS
SELECT
  -- 1/1 Extract specific tag values from the Tags column.
  TRY(element_at(Tags, 'customer')) AS "tag_Customer",
  TRY(element_at(Tags, 'environment')) AS "tag_Environment",
  TRY(element_at(Tags, 'project')) AS "tag_Project",
  -- Tag extraction section END
  *
FROM "${var_glue_table}"
WHERE month >= DATE(to_iso8601(current_date - interval '6' month));