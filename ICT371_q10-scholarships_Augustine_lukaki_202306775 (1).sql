-- ICT371 Advanced Database - Mulungushi University
-- Student: Augustine lukaki (202306775)
-- Question 10: Scholarship Application Assessment
-- PostgreSQL / PL/pgSQL

-- Eligibility requires age 18–25 inclusive, monthly household income no more than K3,000
-- and average mark at least 70. Assessment updates only PENDING applications; the audit
-- trigger records actual status changes.

-- ============================================================
-- 10(a) Tables and seed data
-- Six PENDING applications cover qualifying, non-qualifying and boundary cases across
-- three students.

CREATE TABLE students (
 student_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 student_number VARCHAR(30) UNIQUE NOT NULL,full_name VARCHAR(120) NOT NULL
);
CREATE TABLE applications (
 application_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 student_id BIGINT NOT NULL REFERENCES students(student_id),
 age_at_application INTEGER NOT NULL CHECK(age_at_application>0),
 monthly_income NUMERIC(12,2) NOT NULL CHECK(monthly_income>=0),
 average_mark NUMERIC(5,2) NOT NULL CHECK(average_mark BETWEEN 0 AND 100),
 submitted_on DATE NOT NULL,
 status VARCHAR(10) NOT NULL CHECK(status IN ('PENDING','APPROVED','REJECTED'))
);
CREATE TABLE decision_audit (
 audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 application_id BIGINT NOT NULL REFERENCES applications(application_id),
 old_status VARCHAR(10) NOT NULL,new_status VARCHAR(10) NOT NULL,
 changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO students(student_number,full_name) VALUES
 ('ST001','Alice'),('ST002','Brian'),('ST003','Chipo');
INSERT INTO applications(student_id,age_at_application,monthly_income,average_mark,submitted_on,status) VALUES
 (1,18,3000,70,CURRENT_DATE,'PENDING'),
 (1,25,2500,85,CURRENT_DATE,'PENDING'),
 (2,17,2000,80,CURRENT_DATE,'PENDING'),
 (2,22,3001,90,CURRENT_DATE,'PENDING'),
 (3,24,2800,69.99,CURRENT_DATE,'PENDING'),
 (3,26,1500,95,CURRENT_DATE,'PENDING');

-- ============================================================
-- 10(b) Eligibility function
-- Rejects invalid inputs and checks all three qualifying rules.

CREATE OR REPLACE FUNCTION fn_scholarship_eligible(
 p_age INTEGER,p_income NUMERIC(12,2),p_mark NUMERIC(5,2)
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
 IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL THEN
  RAISE EXCEPTION 'Eligibility inputs cannot be NULL';
 END IF;
 IF p_age<=0 OR p_income<0 OR p_mark<0 OR p_mark>100 THEN
  RAISE EXCEPTION 'Invalid age, income or mark';
 END IF;
 RETURN p_age BETWEEN 18 AND 25 AND p_income<=3000 AND p_mark>=70;
END; $$;

-- ============================================================
-- 10(c) Assessment procedure
-- Requires an existing PENDING application. It calls the eligibility function and changes
-- the status.

CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_age INTEGER;v_income NUMERIC(12,2);v_mark NUMERIC(5,2);v_status VARCHAR(10);
BEGIN
 SELECT age_at_application,monthly_income,average_mark,status
 INTO v_age,v_income,v_mark,v_status
 FROM applications WHERE application_id=p_application_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Application % does not exist',p_application_id; END IF;
 IF v_status<>'PENDING' THEN RAISE EXCEPTION 'Application has already been assessed'; END IF;
 IF fn_scholarship_eligible(v_age,v_income,v_mark) THEN
  UPDATE applications SET status='APPROVED' WHERE application_id=p_application_id;
 ELSE
  UPDATE applications SET status='REJECTED' WHERE application_id=p_application_id;
 END IF;
END; $$;

-- ============================================================
-- 10(d) Decision audit trigger
-- Only an actual change in status creates an audit row.

CREATE OR REPLACE FUNCTION fn_audit_decision()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.status IS DISTINCT FROM OLD.status THEN
  INSERT INTO decision_audit(application_id,old_status,new_status)
  VALUES(NEW.application_id,OLD.status,NEW.status);
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER trg_decision_audit
AFTER UPDATE OF status ON applications FOR EACH ROW
EXECUTE FUNCTION fn_audit_decision();

-- ============================================================
-- 10(e) Approved applicants view
-- Only APPROVED applications are shown. Household income is not included.

CREATE OR REPLACE VIEW v_approved_applicants AS
SELECT s.student_number,s.full_name,a.average_mark,a.status
FROM applications a JOIN students s USING(student_id)
WHERE a.status='APPROVED';

-- ============================================================
-- 10(f) Composite index
-- Status equality followed by submitted_on range is supported by this index.

CREATE INDEX idx_applications_status_date
ON applications(status,submitted_on);
EXPLAIN SELECT application_id,student_id
FROM applications WHERE status='PENDING'
AND submitted_on>=DATE '2026-11-01'
AND submitted_on<DATE '2026-12-01';

-- ============================================================
-- 10(g) Pending assessment and schedule
-- The loop selects only PENDING rows and calls the assessment procedure. Completed
-- applications are skipped on reruns.

CREATE OR REPLACE PROCEDURE pr_assess_pending()
LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
 FOR r IN SELECT application_id FROM applications WHERE status='PENDING'
           ORDER BY application_id
 LOOP
  CALL pr_assess_application(r.application_id);
 END LOOP;
END; $$;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('weekly-scholarship-assessment','0 8 * * 1',
 $$CALL pr_assess_pending()$$);
