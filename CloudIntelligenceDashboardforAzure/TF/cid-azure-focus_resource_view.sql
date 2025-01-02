CREATE OR REPLACE VIEW "focus_resource_view" AS 
SELECT
    AvailabilityZone,
    BillingAccountId,
    BillingAccountName,
    BillingCurrency,
    CAST(BillingPeriodStart AS Date) BillingPeriodStart,
    ChargeCategory,
    ChargeClass,
    ChargeDescription,
    ChargeFrequency,
    CAST((CASE 
        WHEN ("date_trunc"('month', ChargePeriodStart) >= ("date_trunc"('month', current_timestamp) - INTERVAL '3' MONTH)) 
        THEN "date_trunc"('day', ChargePeriodStart) 
        ELSE "date_trunc"('month', ChargePeriodStart) 
    END) AS date) "ChargePeriodStart",
    CommitmentDiscountCategory,
    CommitmentDiscountId,
    CommitmentDiscountName,
    CommitmentDiscountType,
    CommitmentDiscountStatus,
    ConsumedUnit,
    InvoiceIssuerName,
    PricingCategory,
    PricingUnit,
    ProviderName,
    PublisherName,
    RegionId,
    RegionName,
    ResourceId,
    ResourceName,
    ResourceType,
    ServiceCategory,
    ServiceName,
    SkuId,
    SkuPriceId,
    SubAccountId,
    SubAccountName,
    Tags,
    -- 1/4 Extract AWS specific tag values from the Tags MAP column. AWS user tags are lowercase and prefixed with user_
    TRY(element_at(Tags, 'user_customer')) AS "tag_Customer_aws",
    TRY(element_at(Tags, 'user_environment')) AS "tag_Environment_aws",
    TRY(element_at(Tags, 'user_project')) AS "tag_Project_aws",
    -- 2/4 Extract Azure specific tag values from the Tags MAP column
    TRY(element_at(Tags, 'Customer')) AS "tag_Customer_azure",
    TRY(element_at(Tags, 'Environment')) AS "tag_Environment_azure",
    TRY(element_at(Tags, 'Project')) AS "tag_Project_azure",
    -- Tag extraction section END
    billing_period,
    'Azure Only Field' AS x_ResourceGroupName,
    sum(ContractedUnitPrice) ContractedUnitPrice,
    sum(ListUnitPrice) ListUnitPrice,
    sum(BilledCost) BilledCost,
    sum(ContractedCost) ContractedCost,
    sum(EffectiveCost) EffectiveCost,
    sum(ListCost) ListCost,
    sum(ConsumedQuantity) ConsumedQuantity,
    sum(PricingQuantity) PricingQuantity
FROM
    focus_consolidation_view
WHERE 
    ((current_date - INTERVAL '30' DAY) <= ChargePeriodStart) 
    AND (ResourceId <> '') 
    AND (CAST(concat(billing_period, '-01') AS date) >= "date_trunc"('month', (current_date - INTERVAL '30' DAY)))
GROUP BY 
    AvailabilityZone,
    BillingAccountId,
    BillingAccountName,
    BillingCurrency,
    CAST(BillingPeriodStart AS Date),
    ChargeCategory,
    ChargeClass,
    ChargeDescription,
    ChargeFrequency,
    CAST((CASE 
        WHEN ("date_trunc"('month', ChargePeriodStart) >= ("date_trunc"('month', current_timestamp) - INTERVAL '3' MONTH)) 
        THEN "date_trunc"('day', ChargePeriodStart) 
        ELSE "date_trunc"('month', ChargePeriodStart) 
    END) AS date), -- Change is here
    CommitmentDiscountCategory,
    CommitmentDiscountId,
    CommitmentDiscountName,
    CommitmentDiscountType,
    CommitmentDiscountStatus,
    ConsumedUnit,
    InvoiceIssuerName,
    PricingCategory,
    PricingUnit,
    ProviderName,
    PublisherName,
    RegionId,
    RegionName,
    ResourceId,
    ResourceName,
    ResourceType,
    ServiceCategory,
    ServiceName,
    SkuId,
    SkuPriceId,
    SubAccountId,
    SubAccountName,
    Tags,
    -- 3/4 Extract AWS specific tag values from the Tags MAP column. AWS user tags are lowercase and prefixed with user_
    TRY(element_at(Tags, 'user_customer')),
    TRY(element_at(Tags, 'user_environment')),
    TRY(element_at(Tags, 'user_project_aws')),
    -- 4/4 Extract Azure specific tag values from the Tags MAP column
    TRY(element_at(Tags, 'Customer')),
    TRY(element_at(Tags, 'Environment')),
    TRY(element_at(Tags, 'Project')),
    -- Tag extraction section END
    billing_period,
    'Azure Only Field'