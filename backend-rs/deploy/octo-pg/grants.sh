#!/usr/bin/env bash
# Compare table and column grants for the non-owner roles, old vs octo-pg.
Q="select 'T '||table_name||' '||privilege_type from information_schema.role_table_grants where grantee='%s'
   union all select 'C '||table_name||'.'||column_name||' '||privilege_type from information_schema.column_privileges where grantee='%s'
   order by 1"
cmp() {  # label oldcmd newdb role
  a=$(eval "$2" | sort); b=$(docker exec octo-pg psql -U octo_admin -d "$3" -Atc "$(printf "$Q" "$4" "$4")" | sort)
  if [ "$a" = "$b" ]; then echo "same  $1 ($(echo "$a" | grep -c .) grants)"; else echo "DIFF  $1"; diff <(echo "$a") <(echo "$b") | head -8; fi
}
cmp "octopilot: octonotes_credits" "sudo -n -u postgres psql -d octopilot -Atc \"$(printf "$Q" octonotes_credits octonotes_credits)\"" octopilot octonotes_credits
u=$(docker exec cockpit-db printenv POSTGRES_USER)
cmp "cockpit: octonotes_ro" "docker exec cockpit-db psql -U $u -d cockpit -Atc \"$(printf "$Q" octonotes_ro octonotes_ro)\"" cockpit octonotes_ro
cmp "cockpit: intern_rw" "docker exec cockpit-db psql -U $u -d cockpit -Atc \"$(printf "$Q" intern_rw intern_rw)\"" cockpit intern_rw
u=$(docker exec cockpit-vectordb printenv POSTGRES_USER)
cmp "vector: octonotes_ro" "docker exec cockpit-vectordb psql -U $u -d vector -Atc \"$(printf "$Q" octonotes_ro octonotes_ro)\"" vector octonotes_ro
