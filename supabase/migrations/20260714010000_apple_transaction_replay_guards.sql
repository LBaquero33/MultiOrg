-- A StoreKit transaction and original subscription lineage may belong to only
-- one Home Plate subscription context. These constraints close the race window
-- between the Edge Function's ownership lookup and its insert/update.
create unique index if not exists ux_sd_player_subscriptions_apple_transaction
  on public.sd_player_subscriptions(provider_transaction_id)
  where provider = 'apple' and provider_transaction_id is not null;

create unique index if not exists ux_sd_player_subscriptions_apple_original
  on public.sd_player_subscriptions(original_transaction_id)
  where provider = 'apple' and original_transaction_id is not null;
