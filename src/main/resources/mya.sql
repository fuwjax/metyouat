CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;

DROP TABLE IF EXISTS player, status, statusTag, met, metTag CASCADE;
CREATE TABLE IF NOT EXISTS player(id BIGINT PRIMARY KEY, screenName TEXT, name TEXT, originalProfileImageURL TEXT, following BOOLEAN);

CREATE TABLE IF NOT EXISTS status(id BIGINT PRIMARY KEY, playerId BIGINT NOT NULL REFERENCES player, ts BIGINT NOT NULL, message TEXT NOT NULL);

ALTER TABLE player ADD gameStatusId BIGINT REFERENCES status, ADD game CITEXT, ADD targetPlayerId BIGINT;

CREATE TABLE IF NOT EXISTS statusTag(id SERIAL PRIMARY KEY, statusId BIGINT NOT NULL REFERENCES status, tag CITEXT NOT NULL, UNIQUE (statusId, tag));

CREATE TABLE IF NOT EXISTS met(id SERIAL PRIMARY KEY, playerId BIGINT NOT NULL REFERENCES player, targetPlayerId BIGINT NOT NULL REFERENCES player, statusId BIGINT REFERENCES status, targeted BOOLEAN, UNIQUE (playerId, targetPlayerId));

CREATE TABLE IF NOT EXISTS metTag(id SERIAL PRIMARY KEY, metId BIGINT NOT NULL REFERENCES met, tag CITEXT NOT NULL, UNIQUE (metId, tag));

CREATE OR REPLACE FUNCTION savePlayer(id BIGINT, screenName TEXT, name TEXT, originalProfileImageURL TEXT) RETURNS VOID AS
$$
BEGIN
	LOOP
	    -- first try to update the key
	    UPDATE player SET screenName=$2, name=$3, originalProfileImageURL=$4 WHERE player.id = $1;
	    IF found THEN
	        RETURN;
	    END IF;
	    BEGIN
	        INSERT INTO player(id, screenName, name, originalProfileImageURL) VALUES ($1, $2, $3, $4);
	        RETURN;
	    EXCEPTION WHEN unique_violation THEN
	        -- Do nothing, and loop to try the UPDATE again.
	    END;
	END LOOP;
END
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION saveMention(id BIGINT, screenName TEXT, name TEXT) RETURNS VOID AS
$$
BEGIN
	LOOP
	    -- first try to update the key
	    UPDATE player SET screenName=$2, name=$3 WHERE player.id = $1;
	    IF found THEN
	        RETURN;
	    END IF;
	    BEGIN
	        INSERT INTO player(id, screenName, name) VALUES ($1, $2, $3);
	        RETURN;
	    EXCEPTION WHEN unique_violation THEN
	        -- Do nothing, and loop to try the UPDATE again.
	    END;
	END LOOP;
END
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION saveStatus(id BIGINT, playerId BIGINT, ts BIGINT, message TEXT) RETURNS VOID AS
$$
BEGIN
	LOOP
	    -- first try to update the key
	    UPDATE status SET (playerId, ts, message)=($2, $3, $4) WHERE status.id = $1;
	    IF found THEN
	        RETURN;
	    END IF;
	    BEGIN
	        INSERT INTO status(id, playerId, ts, message) VALUES ($1, $2, $3, $4);
	        RETURN;
	    EXCEPTION WHEN unique_violation THEN
	        -- Do nothing, and loop to try the UPDATE again.
	    END;
	END LOOP;
END
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION tagStatus(statusId BIGINT, tag TEXT) RETURNS VOID AS
$$
BEGIN
    INSERT INTO statusTag(statusId, tag) VALUES ($1, $2);
EXCEPTION WHEN unique_violation THEN
    -- Do nothing
END
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION saveMet(playerId BIGINT, targetPlayerId BIGINT, statusId BIGINT) RETURNS BIGINT AS
$$
DECLARE
	metId BIGINT;
BEGIN
    INSERT INTO met(playerId, targetPlayerId, statusId) VALUES ($1, $2, $3) RETURNING id INTO metId;
    RETURN metId;
EXCEPTION WHEN unique_violation THEN
	UPDATE met (statusId) VALUES ($3) WHERE met.playerId=$1 AND met.targetPlayerId=$2 AND met.statusId IS NULL;
    SELECT id INTO metId FROM met WHERE met.playerId=$1 AND met.targetPlayerId=$2;
    RETURN metId;
END
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION tagMet(metId BIGINT, tag TEXT) RETURNS VOID AS
$$
BEGIN
    INSERT INTO metTag(metId, tag) VALUES ($1, $2);
EXCEPTION WHEN unique_violation THEN
    -- Do nothing
END
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION setGame(playerId BIGINT, gameStatusId BIGINT, game TEXT) RETURNS VOID AS
$$
UPDATE player SET gameStatusId=$2, game=$3 WHERE player.id=$1;
$$
LANGUAGE sql;

CREATE OR REPLACE FUNCTION getPlayer(playerId BIGINT) RETURNS player AS
$$
SELECT * FROM player WHERE id=$1;
$$
LANGUAGE sql;

CREATE OR REPLACE FUNCTION getStatusTags(statusId BIGINT) RETURNS SETOF TEXT AS
$$
SELECT tag FROM statusTag WHERE statusTag.statusId=$1;
$$
LANGUAGE sql;

CREATE OR REPLACE FUNCTION newTarget(playerId BIGINT) RETURNS BIGINT AS
$$
DECLARE 
	targetId BIGINT;
BEGIN
	UPDATE met SET targeted=FALSE FROM player WHERE player.id=$1 AND met.playerId=$1 AND met.targetPlayerId=player.targetPlayerId;
	SELECT player.id INTO targetId FROM player LEFT JOIN status ON gameStatusId=status.id WHERE game=(SELECT game FROM player where id=$1) AND player.id NOT IN (SELECT targetPlayerId FROM met WHERE met.playerId=$1) AND player.id != $1 ORDER BY status.ts DESC LIMIT 1;
	UPDATE player SET targetPlayerId=targetId WHERE id=$1;
	IF targetId IS NOT NULL THEN
		INSERT INTO met (playerId, targetPlayerId, targeted) VALUES ($1, targetId, TRUE);
	END IF;
	RETURN targetId;
END
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION followingPlayer(playerId BIGINT) RETURNS VOID AS
$$
BEGIN
	LOOP
	    -- first try to update the key
	    UPDATE player SET following=TRUE WHERE player.id = $1;
	    IF found THEN
	        RETURN;
	    END IF;
	    BEGIN
	        INSERT INTO player(id, following) VALUES ($1, TRUE);
	        RETURN;
	    EXCEPTION WHEN unique_violation THEN
	        -- Do nothing, and loop to try the UPDATE again.
	    END;
	END LOOP;
END
$$
LANGUAGE plpgsql;
