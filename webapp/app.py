import os
import io
import csv
import json
import socket
import datetime
from flask import Flask, render_template, request, redirect, url_for, jsonify, Response
from storage import storage, CATALOG_COURSES

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "aura-campus-erp-secret-key-2026")


def calculate_stats(students):
    total = len(students)
    if total == 0:
        return {
            "total_students": 0,
            "avg_cgpa": 0.0,
            "avg_attendance": 0.0,
            "total_dues": 0.0,
            "total_paid": 0.0,
            "excellent_att": 0,
            "warning_att": 0,
            "critical_att": 0,
            "departments": {},
        }

    total_cgpa = sum(float(s.get("cgpa", 0)) for s in students)
    total_att = sum(float(s.get("attendance", 0)) for s in students)
    total_dues = sum(float(s.get("feesDue", 0)) for s in students)
    total_paid = sum(float(s.get("feesPaid", 0)) for s in students)

    exc = sum(1 for s in students if float(s.get("attendance", 0)) >= 85)
    warn = sum(1 for s in students if 75 <= float(s.get("attendance", 0)) < 85)
    crit = sum(1 for s in students if float(s.get("attendance", 0)) < 75)

    depts = {}
    for s in students:
        d = s.get("department", "General")
        depts[d] = depts.get(d, 0) + 1

    return {
        "total_students": total,
        "avg_cgpa": round(total_cgpa / total, 2),
        "avg_attendance": round(total_att / total, 1),
        "total_dues": round(total_dues, 2),
        "total_paid": round(total_paid, 2),
        "excellent_att": exc,
        "warning_att": warn,
        "critical_att": crit,
        "departments": depts,
    }


@app.route("/")
def index():
    students = storage.get_all_students()
    courses = storage.get_all_courses()
    notices = storage.get_all_notices()
    stats = calculate_stats(students)
    storage_status = storage.get_storage_status()

    # Determine active student for the student portal view
    student_id = request.args.get("student_id")
    current_student = None
    if student_id:
        current_student = storage.get_student_by_id(student_id)
    if not current_student and students:
        # Default to first student (e.g. Samarth Sharma)
        current_student = students[0]

    view_mode = request.args.get("view", "student")  # 'student' or 'admin'
    active_tab = request.args.get("tab", "overview")

    return render_template(
        "index.html",
        students=students,
        current_student=current_student,
        courses=courses,
        notices=notices,
        stats=stats,
        view_mode=view_mode,
        active_tab=active_tab,
        host=socket.gethostname(),
        storage_status=storage_status,
    )


@app.route("/add", methods=["POST"])
def add_student():
    name = request.form.get("name", "").strip()
    course = request.form.get("course", "").strip()
    email = request.form.get("email", "").strip()

    if name and course and email:
        data = {
            "name": name,
            "course": course,
            "email": email,
            "rollNo": request.form.get("rollNo", "").strip(),
            "department": request.form.get("department", "Computer Science & Engineering").strip(),
            "year": request.form.get("year", "1st Year").strip(),
            "semester": request.form.get("semester", "Semester 1").strip(),
            "phone": request.form.get("phone", "+1 (555) 123-4567").strip(),
            "status": request.form.get("status", "Active").strip(),
            "cgpa": request.form.get("cgpa", 8.5),
            "attendance": request.form.get("attendance", 85.0),
            "feesTotal": request.form.get("feesTotal", 4500.0),
            "feesPaid": request.form.get("feesPaid", 4500.0),
            "feesStatus": request.form.get("feesStatus", "Paid"),
            "advisor": request.form.get("advisor", "Prof. Alan Vance").strip(),
            "address": request.form.get("address", "Campus Residence").strip(),
        }
        storage.save_student(data)

    view = request.form.get("view", "admin")
    return redirect(url_for("index", view=view, msg="student_added"))


@app.route("/student/<student_id>/update", methods=["POST"])
def update_student(student_id):
    update_data = {
        "name": request.form.get("name"),
        "course": request.form.get("course"),
        "email": request.form.get("email"),
        "phone": request.form.get("phone"),
        "rollNo": request.form.get("rollNo"),
        "department": request.form.get("department"),
        "year": request.form.get("year"),
        "semester": request.form.get("semester"),
        "status": request.form.get("status"),
        "advisor": request.form.get("advisor"),
        "address": request.form.get("address"),
    }
    if request.form.get("cgpa"):
        try:
            update_data["cgpa"] = float(request.form.get("cgpa"))
        except ValueError:
            pass
    if request.form.get("attendance"):
        try:
            update_data["attendance"] = float(request.form.get("attendance"))
        except ValueError:
            pass
    if request.form.get("feesTotal"):
        try:
            update_data["feesTotal"] = float(request.form.get("feesTotal"))
        except ValueError:
            pass
    if request.form.get("feesPaid"):
        try:
            update_data["feesPaid"] = float(request.form.get("feesPaid"))
        except ValueError:
            pass

    storage.update_student(student_id, update_data)
    view = request.form.get("view", "admin")
    return redirect(url_for("index", view=view, student_id=student_id, msg="student_updated"))


@app.route("/student/<student_id>/delete", methods=["POST"])
def delete_student(student_id):
    storage.delete_student(student_id)
    view = request.form.get("view", "admin")
    return redirect(url_for("index", view=view, msg="student_deleted"))


@app.route("/student/<student_id>/pay-fees", methods=["POST"])
def pay_fees(student_id):
    amount = request.form.get("amount") or request.json.get("amount", 0)
    method = request.form.get("method") or (request.json.get("method") if request.is_json else "Online Portal")
    semester = request.form.get("semester") or (request.json.get("semester") if request.is_json else None)

    receipt, err = storage.record_fee_payment(student_id, amount, method, semester)
    if request.is_json:
        if err:
            return jsonify(success=False, error=err), 400
        return jsonify(success=True, receipt=receipt)

    return redirect(url_for("index", view="student", student_id=student_id, tab="fees", msg="fee_paid"))


@app.route("/student/<student_id>/enroll", methods=["POST"])
def enroll_course(student_id):
    course_code = request.form.get("course_code") or (request.json.get("course_code") if request.is_json else None)
    success, msg = storage.enroll_course(student_id, course_code)
    if request.is_json:
        return jsonify(success=success, message=msg), (200 if success else 400)
    return redirect(url_for("index", view="student", student_id=student_id, tab="courses", msg="enrolled"))


@app.route("/student/<student_id>/drop", methods=["POST"])
def drop_course(student_id):
    course_code = request.form.get("course_code") or (request.json.get("course_code") if request.is_json else None)
    success, msg = storage.drop_course(student_id, course_code)
    if request.is_json:
        return jsonify(success=success, message=msg), (200 if success else 400)
    return redirect(url_for("index", view="student", student_id=student_id, tab="courses", msg="dropped"))


@app.route("/student/<student_id>/attendance-action", methods=["POST"])
def attendance_action(student_id):
    course_code = request.form.get("course_code")
    action_type = request.form.get("action_type")  # 'attend' or 'miss'
    if action_type == "attend":
        storage.update_attendance(student_id, course_code, 1, 1)
    elif action_type == "miss":
        storage.update_attendance(student_id, course_code, 0, 1)

    return redirect(url_for("index", view="student", student_id=student_id, tab="attendance", msg="attendance_updated"))


@app.route("/reset-data", methods=["POST"])
def reset_data():
    storage.reset_demo_data()
    return redirect(url_for("index", msg="data_reset"))


@app.route("/export/csv")
def export_csv():
    students = storage.get_all_students()
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["Student ID", "Roll No", "Name", "Department", "Course", "Semester", "Year", "Email", "Phone", "Status", "CGPA", "Attendance %", "Fee Status", "Fee Total", "Fee Paid", "Fee Due"])
    for s in students:
        writer.writerow([
            s.get("studentId"),
            s.get("rollNo"),
            s.get("name"),
            s.get("department"),
            s.get("course"),
            s.get("semester"),
            s.get("year"),
            s.get("email"),
            s.get("phone"),
            s.get("status"),
            s.get("cgpa"),
            s.get("attendance"),
            s.get("feesStatus"),
            s.get("feesTotal"),
            s.get("feesPaid"),
            s.get("feesDue"),
        ])
    return Response(
        output.getvalue(),
        mimetype="text/csv",
        headers={"Content-Disposition": "attachment;filename=aura_campus_students.csv"}
    )


@app.route("/export/json")
def export_json():
    students = storage.get_all_students()
    return jsonify(students)


@app.route("/api/students")
def api_students():
    students = storage.get_all_students()
    return jsonify(students=students, count=len(students))


@app.route("/api/student/<student_id>")
def api_student(student_id):
    student = storage.get_student_by_id(student_id)
    if not student:
        return jsonify(error="Student not found"), 404
    return jsonify(student)


@app.route("/health")
def health():
    status = storage.get_storage_status()
    students = storage.get_all_students()
    return jsonify(
        status="ok",
        host=socket.gethostname(),
        storage=status["mode"],
        storage_label=status["label"],
        records=len(students),
        timestamp=datetime.datetime.now().isoformat()
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "80")))
