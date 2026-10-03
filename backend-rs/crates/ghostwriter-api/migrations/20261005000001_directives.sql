-- Instructions the user gave mid-run ("keep it formal"). Every later
-- outline, writer and reviser brief on the project carries them.
ALTER TABLE runs ADD COLUMN directives jsonb NOT NULL DEFAULT '[]';
