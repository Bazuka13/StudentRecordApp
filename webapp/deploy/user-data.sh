#!/bin/bash
# EC2 User Data - runs once when each instance starts (used in the Launch Template)
set -e
yum update -y || apt-get update -y
(yum install -y python3 python3-pip || apt-get install -y python3 python3-pip)

mkdir -p /opt/studentapp/templates

cat > /opt/studentapp/storage.py << 'STORAGEEOF'
import os
import json
import sqlite3
import uuid
import datetime
from decimal import Decimal
import boto3
from botocore.exceptions import BotoCoreError, ClientError

TABLE_NAME = os.environ.get("TABLE_NAME", "StudentRecords")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "students.db")

# Sample courses catalog
CATALOG_COURSES = [
    {
        "code": "CS-401",
        "name": "Cloud Computing & Distributed Systems",
        "credits": 4,
        "department": "Computer Science & Engineering",
        "instructor": "Prof. Alan Vance",
        "schedule": "Mon, Wed 10:00 - 11:30 AM",
        "room": "Hall 302",
        "capacity": 60,
        "enrolledCount": 48,
    },
    {
        "code": "CS-405",
        "name": "Deep Learning & Neural Networks",
        "credits": 4,
        "department": "AI & Machine Learning",
        "instructor": "Dr. Anita Rao",
        "schedule": "Tue, Thu 02:00 - 03:30 PM",
        "room": "AI Lab 4",
        "capacity": 50,
        "enrolledCount": 42,
    },
    {
        "code": "CS-412",
        "name": "Modern Web Architectures & APIs",
        "credits": 3,
        "department": "Computer Science & Engineering",
        "instructor": "Prof. David Kim",
        "schedule": "Mon, Wed 02:00 - 03:15 PM",
        "room": "Room 204",
        "capacity": 55,
        "enrolledCount": 51,
    },
    {
        "code": "CS-308",
        "name": "Database Systems & Scalable Storage",
        "credits": 4,
        "department": "Computer Science & Engineering",
        "instructor": "Dr. Elena Thorne",
        "schedule": "Tue, Thu 10:00 - 11:30 AM",
        "room": "Room 108",
        "capacity": 60,
        "enrolledCount": 56,
    },
    {
        "code": "MA-302",
        "name": "Applied Probability & Statistics",
        "credits": 3,
        "department": "Mathematics & Computing",
        "instructor": "Prof. Robert Miller",
        "schedule": "Fri 09:00 - 11:30 AM",
        "room": "Lecture Hall B",
        "capacity": 70,
        "enrolledCount": 65,
    },
    {
        "code": "EN-201",
        "name": "Technical Communication & Ethics",
        "credits": 2,
        "department": "Humanities",
        "instructor": "Prof. Clara Oswald",
        "schedule": "Fri 02:00 - 04:00 PM",
        "room": "Seminar Hall 1",
        "capacity": 80,
        "enrolledCount": 74,
    },
    {
        "code": "CS-480",
        "name": "Cyber Security & Ethical Hacking",
        "credits": 3,
        "department": "Information Security",
        "instructor": "Prof. Marcus Finch",
        "schedule": "Wed, Fri 04:00 - 05:30 PM",
        "room": "Security Lab 2",
        "capacity": 45,
        "enrolledCount": 38,
    },
    {
        "code": "DS-420",
        "name": "Big Data Analytics with Apache Spark",
        "credits": 3,
        "department": "Data Science",
        "instructor": "Dr. Liam Smith",
        "schedule": "Thu 04:00 - 06:30 PM",
        "room": "Data Center Lab",
        "capacity": 40,
        "enrolledCount": 35,
    },
]

CATALOG_NOTICES = [
    {
        "id": "NOT-001",
        "title": "Fall Semester Final Examination Schedule Published",
        "category": "Exam",
        "priority": "Urgent",
        "date": "Today",
        "author": "Controller of Examinations",
        "content": "The comprehensive exam timetable for Fall 2026 has been published. All students must download their digital hall tickets and verify course codes by Nov 10.",
    },
    {
        "id": "NOT-002",
        "title": "Campus Placement Drive: AWS Cloud Architects & SDE Internships",
        "category": "Placement",
        "priority": "High",
        "date": "Yesterday",
        "author": "Career Development Center",
        "content": "Amazon AWS and Microsoft are hosting campus recruitment for 3rd and 4th-year students with CGPA >= 7.5. Submit resumes via the placement portal before Friday.",
    },
    {
        "id": "NOT-003",
        "title": "Semester Tuition & Lab Fee Submission Deadline Notice",
        "category": "Finance",
        "priority": "High",
        "date": "Oct 28",
        "author": "Accounts & Bursar Office",
        "content": "Students with pending dues must clear outstanding semester fees to avoid late charges and course deregistration. Online fee receipt is generated immediately upon payment.",
    },
    {
        "id": "NOT-004",
        "title": "Annual Inter-University Hackathon 'HackNova 2026' Registrations Open",
        "category": "Event",
        "priority": "Normal",
        "date": "Oct 25",
        "author": "Innovation & Student Council",
        "content": "Registrations are open for the 36-hour flagship hackathon with $15,000 in prizes. Team formation and mentorship tracks in AI, Cloud, and Web3.",
    },
    {
        "id": "NOT-005",
        "title": "IEEE Xplore & University Digital Library Remote Access Upgraded",
        "category": "Academic",
        "priority": "Normal",
        "date": "Oct 22",
        "author": "Chief University Librarian",
        "content": "University library has upgraded remote VPN and single-sign-on access for research databases, journals, and ACM digital library.",
    },
]

DEFAULT_TIMETABLE = [
    {"day": "Monday", "time": "10:00 - 11:30 AM", "course": "CS-401 Cloud Computing", "room": "Hall 302", "instructor": "Prof. Alan Vance", "color": "blue"},
    {"day": "Monday", "time": "02:00 - 03:15 PM", "course": "CS-412 Modern Web APIs", "room": "Room 204", "instructor": "Prof. David Kim", "color": "emerald"},
    {"day": "Tuesday", "time": "10:00 - 11:30 AM", "course": "CS-308 Database Systems", "room": "Room 108", "instructor": "Dr. Elena Thorne", "color": "purple"},
    {"day": "Tuesday", "time": "02:00 - 03:30 PM", "course": "CS-405 Deep Learning", "room": "AI Lab 4", "instructor": "Dr. Anita Rao", "color": "amber"},
    {"day": "Wednesday", "time": "10:00 - 11:30 AM", "course": "CS-401 Cloud Computing", "room": "Hall 302", "instructor": "Prof. Alan Vance", "color": "blue"},
    {"day": "Wednesday", "time": "02:00 - 03:15 PM", "course": "CS-412 Modern Web APIs", "room": "Room 204", "instructor": "Prof. David Kim", "color": "emerald"},
    {"day": "Thursday", "time": "10:00 - 11:30 AM", "course": "CS-308 Database Systems", "room": "Room 108", "instructor": "Dr. Elena Thorne", "color": "purple"},
    {"day": "Thursday", "time": "02:00 - 03:30 PM", "course": "CS-405 Deep Learning", "room": "AI Lab 4", "instructor": "Dr. Anita Rao", "color": "amber"},
    {"day": "Friday", "time": "09:00 - 11:30 AM", "course": "MA-302 Applied Probability", "room": "Hall B", "instructor": "Prof. Robert Miller", "color": "rose"},
    {"day": "Friday", "time": "02:00 - 04:00 PM", "course": "EN-201 Technical Ethics", "room": "Seminar 1", "instructor": "Prof. Clara Oswald", "color": "indigo"},
]

SEED_STUDENTS = [
    {
        "studentId": "STU-1001",
        "name": "Samarth Sharma",
        "course": "Cloud Computing",
        "email": "samarth@university.edu",
        "rollNo": "2023CSB1042",
        "department": "Computer Science & Engineering",
        "year": "3rd Year",
        "semester": "Semester 6",
        "phone": "+1 (555) 349-2810",
        "status": "Active",
        "cgpa": 9.24,
        "attendance": 88,
        "feesStatus": "Paid",
        "feesTotal": 4500,
        "feesPaid": 4500,
        "feesDue": 0,
        "advisor": "Dr. Alan Vance",
        "address": "402 North Campus Way, University District",
        "courses": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "instructor": "Prof. Alan Vance", "schedule": "Mon, Wed 10:00 AM", "room": "Hall 302", "attendance": 92, "classesTotal": 24, "classesAttended": 22},
            {"code": "CS-405", "name": "Deep Learning & Neural Networks", "credits": 4, "instructor": "Dr. Anita Rao", "schedule": "Tue, Thu 02:00 PM", "room": "AI Lab 4", "attendance": 88, "classesTotal": 24, "classesAttended": 21},
            {"code": "CS-412", "name": "Modern Web Architectures & APIs", "credits": 3, "instructor": "Prof. David Kim", "schedule": "Mon, Wed 02:00 PM", "room": "Room 204", "attendance": 85, "classesTotal": 20, "classesAttended": 17},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "instructor": "Dr. Elena Thorne", "schedule": "Tue, Thu 10:00 AM", "room": "Room 108", "attendance": 90, "classesTotal": 22, "classesAttended": 20},
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "instructor": "Prof. Robert Miller", "schedule": "Fri 09:00 AM", "room": "Hall B", "attendance": 86, "classesTotal": 14, "classesAttended": 12},
        ],
        "grades": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "grade": "A+", "points": 10.0, "status": "Passed"},
            {"code": "CS-405", "name": "Deep Learning & Neural Networks", "credits": 4, "grade": "A", "points": 9.0, "status": "Passed"},
            {"code": "CS-412", "name": "Modern Web Architectures & APIs", "credits": 3, "grade": "A+", "points": 10.0, "status": "Passed"},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "grade": "A-", "points": 8.7, "status": "Passed"},
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "grade": "A", "points": 9.0, "status": "Passed"},
        ],
        "payments": [
            {"receiptId": "REC-94101", "date": "2026-08-15", "amount": 4500, "method": "Online Banking", "semester": "Fall 2026", "status": "Completed"}
        ]
    },
    {
        "studentId": "STU-1002",
        "name": "Priya Patel",
        "course": "Artificial Intelligence & Data Science",
        "email": "priya.p@university.edu",
        "rollNo": "2024AID2011",
        "department": "AI & Machine Learning",
        "year": "2nd Year",
        "semester": "Semester 4",
        "phone": "+1 (555) 782-9901",
        "status": "Active",
        "cgpa": 8.95,
        "attendance": 94,
        "feesStatus": "Paid",
        "feesTotal": 4500,
        "feesPaid": 4500,
        "feesDue": 0,
        "advisor": "Dr. Anita Rao",
        "address": "128 Oakwood Circle, Apt 4B",
        "courses": [
            {"code": "CS-405", "name": "Deep Learning & Neural Networks", "credits": 4, "instructor": "Dr. Anita Rao", "schedule": "Tue, Thu 02:00 PM", "room": "AI Lab 4", "attendance": 96, "classesTotal": 24, "classesAttended": 23},
            {"code": "DS-420", "name": "Big Data Analytics with Apache Spark", "credits": 3, "instructor": "Dr. Liam Smith", "schedule": "Thu 04:00 PM", "room": "Data Center", "attendance": 92, "classesTotal": 14, "classesAttended": 13},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "instructor": "Dr. Elena Thorne", "schedule": "Tue, Thu 10:00 AM", "room": "Room 108", "attendance": 95, "classesTotal": 22, "classesAttended": 21},
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "instructor": "Prof. Robert Miller", "schedule": "Fri 09:00 AM", "room": "Hall B", "attendance": 93, "classesTotal": 14, "classesAttended": 13},
        ],
        "grades": [
            {"code": "CS-405", "name": "Deep Learning & Neural Networks", "credits": 4, "grade": "A+", "points": 10.0, "status": "Passed"},
            {"code": "DS-420", "name": "Big Data Analytics with Apache Spark", "credits": 3, "grade": "A", "points": 9.0, "status": "Passed"},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "grade": "A", "points": 9.0, "status": "Passed"},
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "grade": "A-", "points": 8.5, "status": "Passed"},
        ],
        "payments": [
            {"receiptId": "REC-93821", "date": "2026-08-14", "amount": 4500, "method": "Credit Card", "semester": "Fall 2026", "status": "Completed"}
        ]
    },
    {
        "studentId": "STU-1003",
        "name": "Alex Rivera",
        "course": "Software Engineering & DevOps",
        "email": "alex.r@university.edu",
        "rollNo": "2023CSB1109",
        "department": "Computer Science & Engineering",
        "year": "3rd Year",
        "semester": "Semester 6",
        "phone": "+1 (555) 431-8842",
        "status": "Active",
        "cgpa": 7.82,
        "attendance": 71,
        "feesStatus": "Partial",
        "feesTotal": 4500,
        "feesPaid": 3000,
        "feesDue": 1500,
        "advisor": "Prof. David Kim",
        "address": "88 Elm Street, Suite 12",
        "courses": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "instructor": "Prof. Alan Vance", "schedule": "Mon, Wed 10:00 AM", "room": "Hall 302", "attendance": 75, "classesTotal": 24, "classesAttended": 18},
            {"code": "CS-412", "name": "Modern Web Architectures & APIs", "credits": 3, "instructor": "Prof. David Kim", "schedule": "Mon, Wed 02:00 PM", "room": "Room 204", "attendance": 70, "classesTotal": 20, "classesAttended": 14},
            {"code": "CS-480", "name": "Cyber Security & Ethical Hacking", "credits": 3, "instructor": "Prof. Marcus Finch", "schedule": "Wed, Fri 04:00 PM", "room": "Sec Lab", "attendance": 68, "classesTotal": 19, "classesAttended": 13},
        ],
        "grades": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "grade": "B+", "points": 8.0, "status": "Passed"},
            {"code": "CS-412", "name": "Modern Web Architectures & APIs", "credits": 3, "grade": "B", "points": 7.5, "status": "Passed"},
            {"code": "CS-480", "name": "Cyber Security & Ethical Hacking", "credits": 3, "grade": "B+", "points": 8.0, "status": "Passed"},
        ],
        "payments": [
            {"receiptId": "REC-92144", "date": "2026-08-20", "amount": 3000, "method": "Debit Card", "semester": "Fall 2026", "status": "Completed"}
        ]
    },
    {
        "studentId": "STU-1004",
        "name": "Marcus Chen",
        "course": "Robotics & Embedded Systems",
        "email": "m.chen@university.edu",
        "rollNo": "2022EEB084",
        "department": "Electrical & Electronics",
        "year": "4th Year",
        "semester": "Semester 8",
        "phone": "+1 (555) 902-1243",
        "status": "Active",
        "cgpa": 9.60,
        "attendance": 91,
        "feesStatus": "Paid",
        "feesTotal": 4800,
        "feesPaid": 4800,
        "feesDue": 0,
        "advisor": "Dr. Harrison Ford",
        "address": "512 Pinecrest Boulevard",
        "courses": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "instructor": "Prof. Alan Vance", "schedule": "Mon, Wed 10:00 AM", "room": "Hall 302", "attendance": 90, "classesTotal": 24, "classesAttended": 21},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "instructor": "Dr. Elena Thorne", "schedule": "Tue, Thu 10:00 AM", "room": "Room 108", "attendance": 92, "classesTotal": 22, "classesAttended": 20},
            {"code": "EN-201", "name": "Technical Communication & Ethics", "credits": 2, "instructor": "Prof. Clara Oswald", "schedule": "Fri 02:00 PM", "room": "Seminar 1", "attendance": 90, "classesTotal": 14, "classesAttended": 13},
        ],
        "grades": [
            {"code": "CS-401", "name": "Cloud Computing & Distributed Systems", "credits": 4, "grade": "O", "points": 10.0, "status": "Passed"},
            {"code": "CS-308", "name": "Database Systems & Scalable Storage", "credits": 4, "grade": "A+", "points": 9.8, "status": "Passed"},
            {"code": "EN-201", "name": "Technical Communication & Ethics", "credits": 2, "grade": "A+", "points": 9.5, "status": "Passed"},
        ],
        "payments": [
            {"receiptId": "REC-91040", "date": "2026-08-10", "amount": 4800, "method": "Bank Transfer", "semester": "Fall 2026", "status": "Completed"}
        ]
    },
    {
        "studentId": "STU-1005",
        "name": "Elena Rostova",
        "course": "Financial Analytics & Management",
        "email": "elena.r@university.edu",
        "rollNo": "2025BBA3019",
        "department": "Business & Management",
        "year": "1st Year",
        "semester": "Semester 2",
        "phone": "+1 (555) 219-5431",
        "status": "Active",
        "cgpa": 8.40,
        "attendance": 82,
        "feesStatus": "Pending",
        "feesTotal": 4200,
        "feesPaid": 1000,
        "feesDue": 3200,
        "advisor": "Dr. Sophia Sterling",
        "address": "19 West End Avenue",
        "courses": [
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "instructor": "Prof. Robert Miller", "schedule": "Fri 09:00 AM", "room": "Hall B", "attendance": 85, "classesTotal": 14, "classesAttended": 12},
            {"code": "EN-201", "name": "Technical Communication & Ethics", "credits": 2, "instructor": "Prof. Clara Oswald", "schedule": "Fri 02:00 PM", "room": "Seminar 1", "attendance": 80, "classesTotal": 14, "classesAttended": 11},
        ],
        "grades": [
            {"code": "MA-302", "name": "Applied Probability & Statistics", "credits": 3, "grade": "A", "points": 8.8, "status": "Passed"},
            {"code": "EN-201", "name": "Technical Communication & Ethics", "credits": 2, "grade": "A-", "points": 8.2, "status": "Passed"},
        ],
        "payments": [
            {"receiptId": "REC-89020", "date": "2026-09-01", "amount": 1000, "method": "Cash Deposit", "semester": "Fall 2026", "status": "Completed"}
        ]
    }
]


class StorageManager:
    def __init__(self):
        self.use_dynamodb = False
        self.dynamodb = None
        self.table = None
        self._init_sqlite()
        self._test_dynamodb()

    def _init_sqlite(self):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS students (
                studentId TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                course TEXT NOT NULL,
                email TEXT NOT NULL,
                rollNo TEXT,
                department TEXT,
                year TEXT,
                semester TEXT,
                phone TEXT,
                status TEXT DEFAULT 'Active',
                cgpa REAL DEFAULT 8.0,
                attendance REAL DEFAULT 85.0,
                feesStatus TEXT DEFAULT 'Paid',
                feesTotal REAL DEFAULT 4500.0,
                feesPaid REAL DEFAULT 4500.0,
                feesDue REAL DEFAULT 0.0,
                advisor TEXT,
                address TEXT,
                courses_json TEXT,
                grades_json TEXT,
                payments_json TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS notices (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                category TEXT NOT NULL,
                priority TEXT NOT NULL,
                date TEXT NOT NULL,
                author TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()

        # Seed initial records if empty
        cursor.execute("SELECT COUNT(*) FROM students")
        count = cursor.fetchone()[0]
        if count == 0:
            for s in SEED_STUDENTS:
                self._insert_sqlite_student(cursor, s)
            for n in CATALOG_NOTICES:
                cursor.execute("""
                    INSERT INTO notices (id, title, category, priority, date, author, content)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (n["id"], n["title"], n["category"], n["priority"], n["date"], n["author"], n["content"]))
            conn.commit()
        conn.close()

    def _insert_sqlite_student(self, cursor, s):
        cursor.execute("""
            INSERT OR REPLACE INTO students (
                studentId, name, course, email, rollNo, department, year, semester,
                phone, status, cgpa, attendance, feesStatus, feesTotal, feesPaid, feesDue,
                advisor, address, courses_json, grades_json, payments_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            s.get("studentId"),
            s.get("name"),
            s.get("course"),
            s.get("email"),
            s.get("rollNo", "2024REG" + s.get("studentId", "001")[-3:]),
            s.get("department", "Computer Science & Engineering"),
            s.get("year", "3rd Year"),
            s.get("semester", "Semester 6"),
            s.get("phone", "+1 (555) 000-0000"),
            s.get("status", "Active"),
            float(s.get("cgpa", 8.0)),
            float(s.get("attendance", 85.0)),
            s.get("feesStatus", "Paid"),
            float(s.get("feesTotal", 4500.0)),
            float(s.get("feesPaid", 4500.0)),
            float(s.get("feesDue", 0.0)),
            s.get("advisor", "Dr. Alan Vance"),
            s.get("address", "Main Campus, University District"),
            json.dumps(s.get("courses", [])),
            json.dumps(s.get("grades", [])),
            json.dumps(s.get("payments", [])),
        ))

    def _test_dynamodb(self):
        try:
            ddb = boto3.resource("dynamodb", region_name=AWS_REGION)
            tbl = ddb.Table(TABLE_NAME)
            # Try a lightweight check
            tbl.table_status
            self.dynamodb = ddb
            self.table = tbl
            self.use_dynamodb = True
        except Exception:
            self.use_dynamodb = False
            self.dynamodb = None
            self.table = None

    def get_storage_status(self):
        return {
            "mode": "dynamodb" if self.use_dynamodb else "local_sqlite",
            "table_name": TABLE_NAME,
            "region": AWS_REGION,
            "sqlite_db": DB_PATH,
            "label": f"AWS DynamoDB ({AWS_REGION})" if self.use_dynamodb else "Local ERP Database (SQLite Synced)"
        }

    def _format_sqlite_row(self, row):
        student_id, name, course, email, roll_no, department, year, semester, phone, status, cgpa, attendance, fees_status, fees_total, fees_paid, fees_due, advisor, address, courses_json, grades_json, payments_json, _ = row
        try:
            courses = json.loads(courses_json) if courses_json else []
        except Exception:
            courses = []
        try:
            grades = json.loads(grades_json) if grades_json else []
        except Exception:
            grades = []
        try:
            payments = json.loads(payments_json) if payments_json else []
        except Exception:
            payments = []

        return {
            "studentId": student_id,
            "name": name,
            "course": course,
            "email": email,
            "rollNo": roll_no or f"REG-{student_id}",
            "department": department or "Computer Science",
            "year": year or "3rd Year",
            "semester": semester or "Semester 6",
            "phone": phone or "+1 (555) 000-0000",
            "status": status or "Active",
            "cgpa": round(float(cgpa or 8.0), 2),
            "attendance": round(float(attendance or 85.0), 1),
            "feesStatus": fees_status or "Paid",
            "feesTotal": float(fees_total or 4500.0),
            "feesPaid": float(fees_paid or 4500.0),
            "feesDue": float(fees_due or 0.0),
            "advisor": advisor or "Dr. Alan Vance",
            "address": address or "Campus Residence",
            "courses": courses,
            "grades": grades,
            "payments": payments,
            "timetable": DEFAULT_TIMETABLE,
        }

    def get_all_students(self):
        if self.use_dynamodb and self.table:
            try:
                resp = self.table.scan()
                items = resp.get("Items", [])
                formatted = []
                for item in items:
                    formatted.append(self._normalize_dynamo_item(item))
                formatted.sort(key=lambda x: x.get("name", "").lower())
                return formatted
            except Exception:
                pass  # Fall back to SQLite

        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM students ORDER BY LOWER(name) ASC")
        rows = cursor.fetchall()
        conn.close()
        return [self._format_sqlite_row(r) for r in rows]

    def _normalize_dynamo_item(self, item):
        res = dict(item)
        if "courses" in res and isinstance(res["courses"], str):
            try:
                res["courses"] = json.loads(res["courses"])
            except Exception:
                res["courses"] = []
        if "grades" in res and isinstance(res["grades"], str):
            try:
                res["grades"] = json.loads(res["grades"])
            except Exception:
                res["grades"] = []
        if "payments" in res and isinstance(res["payments"], str):
            try:
                res["payments"] = json.loads(res["payments"])
            except Exception:
                res["payments"] = []
        res.setdefault("timetable", DEFAULT_TIMETABLE)
        res["cgpa"] = float(res.get("cgpa", 8.0))
        res["attendance"] = float(res.get("attendance", 85.0))
        res["feesTotal"] = float(res.get("feesTotal", 4500.0))
        res["feesPaid"] = float(res.get("feesPaid", 4500.0))
        res["feesDue"] = float(res.get("feesDue", 0.0))
        return res

    def get_student_by_id(self, student_id):
        all_students = self.get_all_students()
        for s in all_students:
            if s.get("studentId") == student_id:
                return s
        return all_students[0] if all_students else None

    def save_student(self, data):
        student_id = data.get("studentId") or str(uuid.uuid4())[:8]
        name = data.get("name", "").strip()
        course = data.get("course", "").strip()
        email = data.get("email", "").strip()
        department = data.get("department", "Computer Science & Engineering").strip()
        roll_no = data.get("rollNo") or f"2026{department[:2].upper()}{student_id[-4:]}"
        year = data.get("year", "1st Year").strip()
        semester = data.get("semester", "Semester 1").strip()
        phone = data.get("phone", "+1 (555) 234-5678").strip()
        status = data.get("status", "Active")
        
        try:
            cgpa = round(float(data.get("cgpa", 8.5)), 2)
        except (ValueError, TypeError):
            cgpa = 8.5

        try:
            attendance = round(float(data.get("attendance", 88.0)), 1)
        except (ValueError, TypeError):
            attendance = 88.0

        try:
            fees_total = float(data.get("feesTotal", 4500.0))
        except (ValueError, TypeError):
            fees_total = 4500.0

        try:
            fees_paid = float(data.get("feesPaid", fees_total))
        except (ValueError, TypeError):
            fees_paid = fees_total

        fees_due = max(0.0, fees_total - fees_paid)
        fees_status = data.get("feesStatus")
        if not fees_status:
            if fees_due == 0:
                fees_status = "Paid"
            elif fees_paid > 0:
                fees_status = "Partial"
            else:
                fees_status = "Pending"

        advisor = data.get("advisor", "Prof. Alan Vance")
        address = data.get("address", "North University Hall, Campus")
        
        courses = data.get("courses")
        if not courses:
            courses = [
                {"code": "CS-401", "name": course or "Cloud Computing", "credits": 4, "instructor": advisor, "schedule": "Mon, Wed 10:00 AM", "room": "Hall 302", "attendance": int(attendance), "classesTotal": 20, "classesAttended": int(20 * (attendance / 100))},
                {"code": "CS-412", "name": "Modern Web Architectures & APIs", "credits": 3, "instructor": "Prof. David Kim", "schedule": "Mon, Wed 02:00 PM", "room": "Room 204", "attendance": int(attendance), "classesTotal": 20, "classesAttended": int(20 * (attendance / 100))},
            ]

        grades = data.get("grades")
        if not grades:
            grades = [
                {"code": "CS-401", "name": course or "Cloud Computing", "credits": 4, "grade": "A", "points": cgpa, "status": "Passed"},
                {"code": "CS-412", "name": "Modern Web Architectures", "credits": 3, "grade": "A-", "points": max(6.0, cgpa - 0.5), "status": "Passed"},
            ]

        payments = data.get("payments", [])
        if not payments and fees_paid > 0:
            payments = [{
                "receiptId": f"REC-{str(uuid.uuid4())[:6].upper()}",
                "date": datetime.date.today().isoformat(),
                "amount": fees_paid,
                "method": "Online Payment",
                "semester": semester,
                "status": "Completed"
            }]

        record = {
            "studentId": student_id,
            "name": name,
            "course": course,
            "email": email,
            "rollNo": roll_no,
            "department": department,
            "year": year,
            "semester": semester,
            "phone": phone,
            "status": status,
            "cgpa": cgpa,
            "attendance": attendance,
            "feesStatus": fees_status,
            "feesTotal": fees_total,
            "feesPaid": fees_paid,
            "feesDue": fees_due,
            "advisor": advisor,
            "address": address,
            "courses": courses,
            "grades": grades,
            "payments": payments,
        }

        # 1. Save to SQLite
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        self._insert_sqlite_student(cursor, record)
        conn.commit()
        conn.close()

        # 2. Save to DynamoDB if available
        if self.use_dynamodb and self.table:
            try:
                dynamo_record = dict(record)
                dynamo_record["cgpa"] = Decimal(str(cgpa))
                dynamo_record["attendance"] = Decimal(str(attendance))
                dynamo_record["feesTotal"] = Decimal(str(fees_total))
                dynamo_record["feesPaid"] = Decimal(str(fees_paid))
                dynamo_record["feesDue"] = Decimal(str(fees_due))
                dynamo_record["courses"] = json.dumps(courses)
                dynamo_record["grades"] = json.dumps(grades)
                dynamo_record["payments"] = json.dumps(payments)
                self.table.put_item(Item=dynamo_record)
            except Exception:
                pass

        return record

    def update_student(self, student_id, data):
        existing = self.get_student_by_id(student_id)
        if not existing:
            return None
        
        for k, v in data.items():
            if v is not None and v != "":
                existing[k] = v

        if "feesPaid" in data or "feesTotal" in data:
            total = float(existing.get("feesTotal", 4500.0))
            paid = float(existing.get("feesPaid", 0.0))
            due = max(0.0, total - paid)
            existing["feesDue"] = due
            if due == 0:
                existing["feesStatus"] = "Paid"
            elif paid > 0:
                existing["feesStatus"] = "Partial"
            else:
                existing["feesStatus"] = "Pending"

        return self.save_student(existing)

    def delete_student(self, student_id):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM students WHERE studentId = ?", (student_id,))
        conn.commit()
        conn.close()

        if self.use_dynamodb and self.table:
            try:
                self.table.delete_item(Key={"studentId": student_id})
            except Exception:
                pass
        return True

    def record_fee_payment(self, student_id, amount, method="Online Gateway", semester=None):
        student = self.get_student_by_id(student_id)
        if not student:
            return None, "Student not found"
        
        amount = float(amount)
        if amount <= 0:
            return None, "Invalid amount"

        current_paid = float(student.get("feesPaid", 0.0))
        new_paid = current_paid + amount
        student["feesPaid"] = new_paid
        total = float(student.get("feesTotal", 4500.0))
        due = max(0.0, total - new_paid)
        student["feesDue"] = due
        if due == 0:
            student["feesStatus"] = "Paid"
        else:
            student["feesStatus"] = "Partial"

        receipt_id = f"REC-{datetime.datetime.now().strftime('%m%d')}-{str(uuid.uuid4())[:4].upper()}"
        payment_record = {
            "receiptId": receipt_id,
            "date": datetime.date.today().isoformat(),
            "time": datetime.datetime.now().strftime("%I:%M %p"),
            "amount": amount,
            "method": method,
            "semester": semester or student.get("semester", "Semester 6"),
            "status": "Completed"
        }
        
        payments = student.get("payments", [])
        payments.insert(0, payment_record)
        student["payments"] = payments

        self.save_student(student)
        return payment_record, None

    def enroll_course(self, student_id, course_code):
        student = self.get_student_by_id(student_id)
        if not student:
            return False, "Student not found"
        
        # Check if already enrolled
        for c in student.get("courses", []):
            if c.get("code") == course_code:
                return False, "Already registered in this course"

        target_course = next((c for c in CATALOG_COURSES if c["code"] == course_code), None)
        if not target_course:
            return False, "Course code not found in catalog"

        new_course_entry = {
            "code": target_course["code"],
            "name": target_course["name"],
            "credits": target_course["credits"],
            "instructor": target_course["instructor"],
            "schedule": target_course["schedule"],
            "room": target_course["room"],
            "attendance": 100,
            "classesTotal": 1,
            "classesAttended": 1,
        }
        courses = student.get("courses", [])
        courses.append(new_course_entry)
        student["courses"] = courses
        self.save_student(student)
        return True, "Enrolled successfully"

    def drop_course(self, student_id, course_code):
        student = self.get_student_by_id(student_id)
        if not student:
            return False, "Student not found"
        
        courses = [c for c in student.get("courses", []) if c.get("code") != course_code]
        if len(courses) == len(student.get("courses", [])):
            return False, "Course was not in your registration list"

        student["courses"] = courses
        self.save_student(student)
        return True, "Course dropped successfully"

    def update_attendance(self, student_id, course_code, attended_delta, total_delta):
        student = self.get_student_by_id(student_id)
        if not student:
            return False, "Student not found"

        found = False
        for c in student.get("courses", []):
            if c.get("code") == course_code:
                c["classesAttended"] = max(0, c.get("classesAttended", 0) + attended_delta)
                c["classesTotal"] = max(1, c.get("classesTotal", 1) + total_delta)
                c["attendance"] = round((c["classesAttended"] / c["classesTotal"]) * 100, 1)
                found = True
                break

        if found:
            # Recalculate overall attendance
            all_att = sum(c.get("classesAttended", 0) for c in student["courses"])
            all_tot = sum(c.get("classesTotal", 1) for c in student["courses"])
            if all_tot > 0:
                student["attendance"] = round((all_att / all_tot) * 100, 1)
            self.save_student(student)
            return True, "Attendance updated"
        return False, "Course not found for this student"

    def get_all_courses(self):
        return CATALOG_COURSES

    def get_all_notices(self):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT id, title, category, priority, date, author, content FROM notices ORDER BY created_at DESC")
        rows = cursor.fetchall()
        conn.close()
        return [
            {
                "id": r[0],
                "title": r[1],
                "category": r[2],
                "priority": r[3],
                "date": r[4],
                "author": r[5],
                "content": r[6]
            }
            for r in rows
        ]

    def reset_demo_data(self):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM students")
        cursor.execute("DELETE FROM notices")
        for s in SEED_STUDENTS:
            self._insert_sqlite_student(cursor, s)
        for n in CATALOG_NOTICES:
            cursor.execute("""
                INSERT INTO notices (id, title, category, priority, date, author, content)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (n["id"], n["title"], n["category"], n["priority"], n["date"], n["author"], n["content"]))
        conn.commit()
        conn.close()

        if self.use_dynamodb and self.table:
            try:
                for s in SEED_STUDENTS:
                    self.save_student(s)
            except Exception:
                pass
        return True


storage = StorageManager()

STORAGEEOF

cat > /opt/studentapp/app.py << 'APPEOF'
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

APPEOF

cat > /opt/studentapp/templates/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AuraCampus ERP - Unified Student & Academic Management System</title>
  <meta name="description" content="Next-generation Campus ERP and Student Information System with real-time academic records, attendance analytics, fee payments, and timetable.">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
  
  <style>
    :root {
      --font-heading: 'Outfit', sans-serif;
      --font-body: 'Plus Jakarta Sans', sans-serif;
      
      /* Dark Theme (Default) */
      --bg-base: #0b0f19;
      --bg-surface: #111827;
      --bg-surface-elevated: #1a2236;
      --bg-surface-hover: #222d46;
      --border-subtle: rgba(255, 255, 255, 0.08);
      --border-strong: rgba(255, 255, 255, 0.16);
      
      --text-main: #f3f4f6;
      --text-muted: #9ca3af;
      --text-dim: #6b7280;
      
      --primary: #4f46e5;
      --primary-hover: #4338ca;
      --primary-glow: rgba(79, 70, 229, 0.25);
      --secondary: #06b6d4;
      --accent: #8b5cf6;
      
      --success: #10b981;
      --success-glow: rgba(16, 185, 129, 0.2);
      --warning: #f59e0b;
      --warning-glow: rgba(245, 158, 11, 0.2);
      --danger: #ef4444;
      --danger-glow: rgba(239, 68, 68, 0.2);
      --info: #3b82f6;
      
      --card-radius: 16px;
      --btn-radius: 10px;
      --shadow-sm: 0 2px 4px rgba(0, 0, 0, 0.3);
      --shadow-md: 0 8px 24px rgba(0, 0, 0, 0.4);
      --shadow-lg: 0 16px 40px rgba(0, 0, 0, 0.5);
      --transition: all 0.25s cubic-bezier(0.16, 1, 0.3, 1);
    }

    [data-theme="light"] {
      --bg-base: #f4f6fb;
      --bg-surface: #ffffff;
      --bg-surface-elevated: #f8fafc;
      --bg-surface-hover: #f1f5f9;
      --border-subtle: rgba(0, 0, 0, 0.08);
      --border-strong: rgba(0, 0, 0, 0.14);
      
      --text-main: #0f172a;
      --text-muted: #475569;
      --text-dim: #94a3b8;
      
      --primary: #4f46e5;
      --primary-hover: #4338ca;
      --primary-glow: rgba(79, 70, 229, 0.15);
      --secondary: #0891b2;
      --accent: #7c3aed;
      
      --shadow-sm: 0 1px 3px rgba(0, 0, 0, 0.06);
      --shadow-md: 0 6px 16px rgba(0, 0, 0, 0.08);
      --shadow-lg: 0 12px 32px rgba(0, 0, 0, 0.1);
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }
    
    body {
      font-family: var(--font-body);
      background-color: var(--bg-base);
      color: var(--text-main);
      min-height: 100vh;
      line-height: 1.5;
      overflow-x: hidden;
      transition: background-color 0.3s ease, color 0.3s ease;
    }

    h1, h2, h3, h4, h5, h6 {
      font-family: var(--font-heading);
      letter-spacing: -0.02em;
      font-weight: 700;
    }

    /* Top Navigation Bar */
    .navbar {
      position: sticky;
      top: 0;
      z-index: 50;
      background: rgba(17, 24, 39, 0.85);
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      border-bottom: 1px solid var(--border-subtle);
      padding: 0.75rem 1.5rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 1rem;
    }
    [data-theme="light"] .navbar {
      background: rgba(255, 255, 255, 0.88);
    }

    .nav-brand {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      text-decoration: none;
      color: var(--text-main);
    }
    .brand-logo-icon {
      width: 42px;
      height: 42px;
      border-radius: 12px;
      background: linear-gradient(135deg, #4f46e5 0%, #06b6d4 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      color: white;
      font-size: 1.3rem;
      box-shadow: 0 4px 14px var(--primary-glow);
    }
    .brand-title {
      font-size: 1.25rem;
      font-weight: 800;
      display: flex;
      align-items: center;
      gap: 0.4rem;
    }
    .brand-title span {
      background: linear-gradient(135deg, #818cf8 0%, #38bdf8 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .brand-subtitle {
      font-size: 0.72rem;
      color: var(--text-muted);
      letter-spacing: 0.05em;
      text-transform: uppercase;
      font-weight: 600;
    }

    .nav-center {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      background: var(--bg-surface-elevated);
      padding: 4px;
      border-radius: 12px;
      border: 1px solid var(--border-subtle);
    }
    .mode-tab-btn {
      padding: 6px 16px;
      border-radius: 8px;
      border: none;
      background: transparent;
      color: var(--text-muted);
      font-size: 0.85rem;
      font-weight: 600;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 6px;
      transition: var(--transition);
      text-decoration: none;
    }
    .mode-tab-btn.active {
      background: var(--primary);
      color: #fff;
      box-shadow: 0 2px 8px var(--primary-glow);
    }
    .mode-tab-btn:hover:not(.active) {
      color: var(--text-main);
      background: var(--bg-surface-hover);
    }

    .nav-actions {
      display: flex;
      align-items: center;
      gap: 0.75rem;
    }

    /* Student Switcher Selector */
    .student-switcher-select {
      background: var(--bg-surface-elevated);
      color: var(--text-main);
      border: 1px solid var(--border-strong);
      padding: 6px 12px;
      border-radius: 8px;
      font-size: 0.85rem;
      font-weight: 500;
      cursor: pointer;
      outline: none;
    }

    .badge-status {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 4px 10px;
      border-radius: 20px;
      font-size: 0.75rem;
      font-weight: 600;
      background: var(--bg-surface-elevated);
      border: 1px solid var(--border-subtle);
      color: var(--text-muted);
    }
    .status-dot {
      width: 7px;
      height: 7px;
      border-radius: 50%;
      background: var(--success);
      box-shadow: 0 0 8px var(--success);
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.5; transform: scale(1.2); }
      100% { opacity: 1; transform: scale(1); }
    }

    .btn-icon {
      width: 38px;
      height: 38px;
      border-radius: 10px;
      display: flex;
      align-items: center;
      justify-content: center;
      background: var(--bg-surface-elevated);
      border: 1px solid var(--border-subtle);
      color: var(--text-main);
      cursor: pointer;
      transition: var(--transition);
      font-size: 0.95rem;
    }
    .btn-icon:hover {
      background: var(--bg-surface-hover);
      color: var(--primary);
      border-color: var(--border-strong);
    }

    .btn-primary {
      background: linear-gradient(135deg, var(--primary) 0%, #6366f1 100%);
      color: white;
      border: none;
      padding: 8px 16px;
      border-radius: var(--btn-radius);
      font-weight: 600;
      font-size: 0.85rem;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: var(--transition);
      box-shadow: 0 3px 10px var(--primary-glow);
      text-decoration: none;
    }
    .btn-primary:hover {
      opacity: 0.95;
      transform: translateY(-1px);
      box-shadow: 0 5px 16px var(--primary-glow);
    }
    .btn-secondary {
      background: var(--bg-surface-elevated);
      color: var(--text-main);
      border: 1px solid var(--border-strong);
      padding: 8px 14px;
      border-radius: var(--btn-radius);
      font-weight: 600;
      font-size: 0.85rem;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: var(--transition);
      text-decoration: none;
    }
    .btn-secondary:hover {
      background: var(--bg-surface-hover);
      border-color: var(--border-strong);
    }

    /* Main Container */
    .app-layout {
      max-width: 1440px;
      margin: 0 auto;
      padding: 1.5rem;
      display: flex;
      flex-direction: column;
      gap: 1.5rem;
    }

    /* Glass Cards */
    .card {
      background: var(--bg-surface);
      border: 1px solid var(--border-subtle);
      border-radius: var(--card-radius);
      padding: 1.5rem;
      box-shadow: var(--shadow-sm);
      transition: var(--transition);
      position: relative;
    }
    .card:hover {
      border-color: var(--border-strong);
    }

    /* Student Hero Profile Banner */
    .student-hero {
      background: linear-gradient(135deg, rgba(79, 70, 229, 0.12) 0%, rgba(6, 182, 212, 0.08) 100%), var(--bg-surface);
      border: 1px solid rgba(99, 102, 241, 0.2);
      border-radius: var(--card-radius);
      padding: 1.75rem;
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      align-items: center;
      gap: 1.5rem;
      box-shadow: var(--shadow-md);
      position: relative;
      overflow: hidden;
    }
    .student-hero::before {
      content: '';
      position: absolute;
      top: -50px;
      right: -50px;
      width: 200px;
      height: 200px;
      background: radial-gradient(circle, rgba(99, 102, 241, 0.25) 0%, transparent 70%);
      pointer-events: none;
    }

    .hero-profile-info {
      display: flex;
      align-items: center;
      gap: 1.25rem;
    }
    .avatar-wrapper {
      position: relative;
    }
    .student-avatar-lg {
      width: 82px;
      height: 82px;
      border-radius: 20px;
      background: linear-gradient(135deg, #4f46e5 0%, #ec4899 100%);
      color: white;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 2rem;
      font-weight: 700;
      box-shadow: 0 8px 24px rgba(79, 70, 229, 0.35);
      border: 3px solid rgba(255, 255, 255, 0.2);
    }
    .avatar-badge-active {
      position: absolute;
      bottom: -4px;
      right: -4px;
      background: var(--success);
      color: white;
      font-size: 0.65rem;
      font-weight: 700;
      padding: 2px 7px;
      border-radius: 10px;
      border: 2px solid var(--bg-surface);
      text-transform: uppercase;
    }

    .student-meta h1 {
      font-size: 1.75rem;
      margin-bottom: 0.25rem;
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }
    .student-meta .roll-chip {
      background: var(--bg-surface-elevated);
      color: var(--secondary);
      font-size: 0.8rem;
      font-weight: 700;
      padding: 3px 10px;
      border-radius: 6px;
      border: 1px solid var(--border-subtle);
      font-family: monospace;
    }
    .student-submeta {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 1rem;
      color: var(--text-muted);
      font-size: 0.875rem;
      margin-top: 0.35rem;
    }
    .student-submeta span {
      display: inline-flex;
      align-items: center;
      gap: 5px;
    }

    .hero-actions {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.75rem;
    }

    /* KPI Stats Grid */
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(230px, 1fr));
      gap: 1rem;
    }
    .stat-card {
      background: var(--bg-surface);
      border: 1px solid var(--border-subtle);
      border-radius: var(--card-radius);
      padding: 1.25rem;
      display: flex;
      align-items: center;
      gap: 1rem;
      box-shadow: var(--shadow-sm);
      transition: var(--transition);
      position: relative;
      overflow: hidden;
    }
    .stat-card:hover {
      transform: translateY(-2px);
      box-shadow: var(--shadow-md);
      border-color: var(--border-strong);
    }
    .stat-icon {
      width: 52px;
      height: 52px;
      border-radius: 14px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 1.4rem;
      flex-shrink: 0;
    }
    .stat-icon.indigo { background: rgba(79, 70, 229, 0.15); color: #818cf8; }
    .stat-icon.cyan { background: rgba(6, 182, 212, 0.15); color: #22d3ee; }
    .stat-icon.emerald { background: rgba(16, 185, 129, 0.15); color: #34d399; }
    .stat-icon.amber { background: rgba(245, 158, 11, 0.15); color: #fbbf24; }
    .stat-icon.rose { background: rgba(239, 68, 68, 0.15); color: #f87171; }

    .stat-content {
      flex: 1;
    }
    .stat-label {
      font-size: 0.75rem;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.05em;
      font-weight: 600;
    }
    .stat-value {
      font-size: 1.6rem;
      font-weight: 800;
      color: var(--text-main);
      line-height: 1.2;
      margin: 2px 0;
    }
    .stat-subtext {
      font-size: 0.75rem;
      color: var(--text-dim);
      display: flex;
      align-items: center;
      gap: 4px;
    }

    /* Sub Tabs inside Student Portal */
    .portal-tabs {
      display: flex;
      overflow-x: auto;
      gap: 0.5rem;
      padding-bottom: 4px;
      border-bottom: 1px solid var(--border-subtle);
    }
    .portal-tab-btn {
      padding: 0.6rem 1.1rem;
      background: transparent;
      border: none;
      color: var(--text-muted);
      font-weight: 600;
      font-size: 0.875rem;
      cursor: pointer;
      border-radius: 8px;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      white-space: nowrap;
      transition: var(--transition);
      text-decoration: none;
    }
    .portal-tab-btn:hover {
      color: var(--text-main);
      background: var(--bg-surface-elevated);
    }
    .portal-tab-btn.active {
      color: #fff;
      background: var(--primary);
      box-shadow: 0 2px 8px var(--primary-glow);
    }

    /* Content Layout Grids */
    .two-col-grid {
      display: grid;
      grid-template-columns: 2fr 1fr;
      gap: 1.5rem;
    }
    @media (max-width: 1024px) {
      .two-col-grid { grid-template-columns: 1fr; }
    }

    /* Table Styles */
    .erp-table-wrapper {
      width: 100%;
      overflow-x: auto;
      border-radius: 12px;
      border: 1px solid var(--border-subtle);
      background: var(--bg-surface);
    }
    table.erp-table {
      width: 100%;
      border-collapse: collapse;
      text-align: left;
      font-size: 0.875rem;
    }
    table.erp-table th {
      background: var(--bg-surface-elevated);
      color: var(--text-muted);
      font-weight: 600;
      text-transform: uppercase;
      font-size: 0.72rem;
      letter-spacing: 0.05em;
      padding: 12px 16px;
      border-bottom: 1px solid var(--border-subtle);
    }
    table.erp-table td {
      padding: 14px 16px;
      border-bottom: 1px solid var(--border-subtle);
      color: var(--text-main);
      vertical-align: middle;
    }
    table.erp-table tr:last-child td {
      border-bottom: none;
    }
    table.erp-table tr:hover td {
      background: var(--bg-surface-hover);
    }

    /* Badges & Pills */
    .pill {
      display: inline-flex;
      align-items: center;
      gap: 5px;
      padding: 3px 9px;
      border-radius: 20px;
      font-size: 0.75rem;
      font-weight: 600;
    }
    .pill-success { background: var(--success-glow); color: #34d399; border: 1px solid rgba(16, 185, 129, 0.3); }
    .pill-warning { background: var(--warning-glow); color: #fbbf24; border: 1px solid rgba(245, 158, 11, 0.3); }
    .pill-danger { background: var(--danger-glow); color: #f87171; border: 1px solid rgba(239, 68, 68, 0.3); }
    .pill-info { background: rgba(59, 130, 246, 0.15); color: #60a5fa; border: 1px solid rgba(59, 130, 246, 0.3); }
    .pill-purple { background: rgba(139, 92, 246, 0.15); color: #a78bfa; border: 1px solid rgba(139, 92, 246, 0.3); }

    /* Progress bar */
    .progress-track {
      width: 100%;
      height: 8px;
      background: var(--bg-surface-elevated);
      border-radius: 10px;
      overflow: hidden;
      position: relative;
    }
    .progress-fill {
      height: 100%;
      border-radius: 10px;
      transition: width 0.6s ease;
    }
    .progress-fill.green { background: linear-gradient(90deg, #10b981, #34d399); }
    .progress-fill.amber { background: linear-gradient(90deg, #f59e0b, #fbbf24); }
    .progress-fill.red { background: linear-gradient(90deg, #ef4444, #f87171); }
    .progress-fill.blue { background: linear-gradient(90deg, #4f46e5, #06b6d4); }

    /* Interactive Bunk / Safe-Leave Calculator Widget */
    .bunk-calculator {
      background: linear-gradient(135deg, rgba(30, 41, 59, 0.6) 0%, rgba(15, 23, 42, 0.8) 100%);
      border: 1px solid rgba(99, 102, 241, 0.25);
      border-radius: var(--card-radius);
      padding: 1.5rem;
      position: relative;
      overflow: hidden;
    }
    .calc-slider-box {
      margin: 1.25rem 0;
    }
    .calc-slider-box input[type="range"] {
      width: 100%;
      accent-color: var(--primary);
      cursor: pointer;
    }
    .calc-result-box {
      background: var(--bg-surface-elevated);
      border-radius: 12px;
      padding: 1rem;
      border: 1px solid var(--border-subtle);
      margin-top: 1rem;
      display: flex;
      align-items: center;
      gap: 1rem;
    }
    .calc-result-icon {
      width: 48px;
      height: 48px;
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 1.5rem;
      flex-shrink: 0;
    }
    .calc-result-icon.safe { background: var(--success-glow); color: #34d399; }
    .calc-result-icon.danger { background: var(--danger-glow); color: #f87171; }

    /* Timetable Grid */
    .timetable-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 1rem;
    }
    .timetable-day-col {
      background: var(--bg-surface);
      border: 1px solid var(--border-subtle);
      border-radius: 14px;
      padding: 1rem;
    }
    .day-header {
      font-size: 0.9rem;
      font-weight: 700;
      color: var(--secondary);
      border-bottom: 1px solid var(--border-subtle);
      padding-bottom: 0.5rem;
      margin-bottom: 0.75rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .class-slot-card {
      background: var(--bg-surface-elevated);
      border-left: 4px solid var(--primary);
      border-radius: 8px;
      padding: 10px;
      margin-bottom: 0.75rem;
      font-size: 0.8rem;
      transition: var(--transition);
    }
    .class-slot-card:hover {
      transform: translateX(3px);
      background: var(--bg-surface-hover);
    }
    .class-time {
      font-size: 0.7rem;
      color: var(--text-muted);
      font-weight: 600;
      margin-bottom: 2px;
    }
    .class-title {
      font-weight: 700;
      color: var(--text-main);
      font-size: 0.82rem;
    }
    .class-room {
      color: var(--text-dim);
      font-size: 0.72rem;
      margin-top: 4px;
      display: flex;
      align-items: center;
      gap: 4px;
    }

    /* Digital Student ID Card */
    .id-card-container {
      max-width: 440px;
      margin: 0 auto;
      perspective: 1000px;
    }
    .id-card {
      background: linear-gradient(135deg, #1e1b4b 0%, #0f172a 100%);
      border: 1px solid rgba(255, 255, 255, 0.15);
      border-radius: 20px;
      padding: 1.75rem;
      color: #fff;
      box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6);
      position: relative;
      overflow: hidden;
    }
    .id-card::before {
      content: '';
      position: absolute;
      top: -30%;
      right: -20%;
      width: 250px;
      height: 250px;
      background: radial-gradient(circle, rgba(99, 102, 241, 0.35) 0%, transparent 70%);
      pointer-events: none;
    }
    .id-card-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      border-bottom: 1px solid rgba(255, 255, 255, 0.1);
      padding-bottom: 1rem;
      margin-bottom: 1.25rem;
    }
    .id-university-name {
      font-size: 1.1rem;
      font-weight: 800;
      letter-spacing: -0.01em;
      background: linear-gradient(90deg, #ffffff, #cbd5e1);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .id-card-body {
      display: flex;
      gap: 1.25rem;
      align-items: center;
    }
    .id-photo {
      width: 90px;
      height: 105px;
      border-radius: 12px;
      background: linear-gradient(135deg, #4f46e5 0%, #ec4899 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 2.2rem;
      font-weight: 800;
      color: white;
      border: 2px solid rgba(255, 255, 255, 0.3);
      flex-shrink: 0;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
    }
    .id-details {
      flex: 1;
      font-size: 0.8rem;
    }
    .id-student-name {
      font-size: 1.15rem;
      font-weight: 800;
      color: #fff;
      margin-bottom: 2px;
    }
    .id-field-row {
      display: flex;
      justify-content: space-between;
      margin: 4px 0;
      color: #94a3b8;
    }
    .id-field-val {
      font-weight: 600;
      color: #f1f5f9;
    }
    .id-card-footer {
      margin-top: 1.25rem;
      padding-top: 0.75rem;
      border-top: 1px solid rgba(255, 255, 255, 0.1);
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .barcode-simulation {
      font-family: monospace;
      letter-spacing: 5px;
      font-weight: 700;
      font-size: 0.85rem;
      color: #94a3b8;
      background: rgba(255, 255, 255, 0.05);
      padding: 4px 8px;
      border-radius: 4px;
    }

    /* Notice Board Item */
    .notice-item {
      padding: 1rem;
      border-radius: 12px;
      background: var(--bg-surface-elevated);
      border: 1px solid var(--border-subtle);
      margin-bottom: 0.75rem;
      transition: var(--transition);
    }
    .notice-item:hover {
      border-color: var(--border-strong);
      transform: translateX(2px);
    }
    .notice-top {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 0.35rem;
    }
    .notice-title {
      font-size: 0.95rem;
      font-weight: 700;
      color: var(--text-main);
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .notice-content {
      font-size: 0.825rem;
      color: var(--text-muted);
      margin: 0.35rem 0;
      line-height: 1.45;
    }
    .notice-meta {
      font-size: 0.72rem;
      color: var(--text-dim);
      display: flex;
      gap: 1rem;
    }

    /* Modal Styles */
    .modal-backdrop {
      position: fixed;
      inset: 0;
      background: rgba(0, 0, 0, 0.75);
      backdrop-filter: blur(8px);
      z-index: 100;
      display: none;
      align-items: center;
      justify-content: center;
      padding: 1rem;
    }
    .modal-backdrop.open {
      display: flex;
    }
    .modal-window {
      background: var(--bg-surface);
      border: 1px solid var(--border-strong);
      border-radius: 20px;
      width: 100%;
      max-width: 600px;
      max-height: 90vh;
      overflow-y: auto;
      box-shadow: var(--shadow-lg);
      padding: 1.75rem;
      animation: modalIn 0.25s cubic-bezier(0.16, 1, 0.3, 1);
    }
    @keyframes modalIn {
      from { opacity: 0; transform: scale(0.95) translateY(10px); }
      to { opacity: 1; transform: scale(1) translateY(0); }
    }
    .modal-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 1.25rem;
      padding-bottom: 0.75rem;
      border-bottom: 1px solid var(--border-subtle);
    }
    .form-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 1rem;
    }
    .form-group {
      margin-bottom: 1rem;
    }
    .form-group.full-width {
      grid-column: span 2;
    }
    .form-label {
      display: block;
      font-size: 0.78rem;
      font-weight: 600;
      color: var(--text-muted);
      margin-bottom: 0.35rem;
      text-transform: uppercase;
      letter-spacing: 0.03em;
    }
    .form-control {
      width: 100%;
      padding: 9px 13px;
      background: var(--bg-surface-elevated);
      border: 1px solid var(--border-strong);
      border-radius: 8px;
      color: var(--text-main);
      font-size: 0.875rem;
      font-family: inherit;
      outline: none;
      transition: var(--transition);
    }
    .form-control:focus {
      border-color: var(--primary);
      box-shadow: 0 0 0 3px var(--primary-glow);
    }

    /* Admin Quick Add Bar (Backward Compatible Form) */
    .quick-add-bar {
      background: var(--bg-surface-elevated);
      border: 1px dashed var(--border-strong);
      border-radius: var(--card-radius);
      padding: 1.25rem;
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.75rem;
      margin-bottom: 1rem;
    }
    .quick-add-bar input {
      flex: 1;
      min-width: 180px;
    }

    /* Filter & Search Toolbar */
    .table-toolbar {
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      align-items: center;
      gap: 1rem;
      margin-bottom: 1rem;
    }
    .search-box {
      position: relative;
      flex: 1;
      max-width: 360px;
    }
    .search-box i {
      position: absolute;
      left: 12px;
      top: 50%;
      transform: translateY(-50%);
      color: var(--text-dim);
      font-size: 0.85rem;
    }
    .search-box input {
      padding-left: 36px;
    }

    .filter-actions {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 0.5rem;
    }

    /* Toast Notification */
    .toast-container {
      position: fixed;
      bottom: 24px;
      right: 24px;
      z-index: 200;
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
    .toast {
      background: var(--bg-surface-elevated);
      color: var(--text-main);
      border: 1px solid var(--border-strong);
      padding: 12px 18px;
      border-radius: 12px;
      box-shadow: var(--shadow-lg);
      display: flex;
      align-items: center;
      gap: 10px;
      font-size: 0.85rem;
      font-weight: 500;
      animation: slideIn 0.3s ease;
    }
    .toast.success { border-left: 4px solid var(--success); }
    @keyframes slideIn {
      from { transform: translateX(100%); opacity: 0; }
      to { transform: translateX(0); opacity: 1; }
    }

    /* Footer */
    .footer {
      margin-top: 2rem;
      padding: 1.5rem 0;
      border-top: 1px solid var(--border-subtle);
      color: var(--text-dim);
      font-size: 0.825rem;
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      align-items: center;
      gap: 1rem;
    }
    .footer b { color: var(--text-main); }

    /* Print View for Transcripts and Receipts */
    @media print {
      body { background: #fff !important; color: #000 !important; }
      .navbar, .portal-tabs, .btn-primary, .btn-secondary, .quick-add-bar, .table-toolbar, .footer { display: none !important; }
      .card { border: 1px solid #ccc !important; box-shadow: none !important; }
    }
  </style>
</head>
<body>

  <!-- Top Sticky Navigation Bar -->
  <header class="navbar">
    <a href="{{ url_for('index') }}" class="nav-brand">
      <div class="brand-logo-icon">
        <i class="fa-solid fa-graduation-cap"></i>
      </div>
      <div>
        <div class="brand-title">Aura<span>Campus</span> <span style="font-size: 0.75rem; background: var(--bg-surface-elevated); padding: 2px 6px; border-radius: 4px; color: var(--secondary); font-weight: 700;">ERP 3.2</span></div>
        <div class="brand-subtitle">Student & Institutional Management</div>
      </div>
    </a>

    <!-- Dual Persona Switcher (Student Portal vs Admin ERP) -->
    <div class="nav-center">
      <a href="{{ url_for('index', view='student', student_id=current_student.studentId if current_student else '') }}" 
         class="mode-tab-btn {% if view_mode == 'student' %}active{% endif %}">
        <i class="fa-solid fa-user-graduate"></i>
        <span>Student Portal</span>
      </a>
      <a href="{{ url_for('index', view='admin') }}" 
         class="mode-tab-btn {% if view_mode == 'admin' %}active{% endif %}">
        <i class="fa-solid fa-sliders"></i>
        <span>Faculty & Admin ERP</span>
      </a>
    </div>

    <!-- Right Controls -->
    <div class="nav-actions">
      <!-- Switch Student Dropdown -->
      {% if view_mode == 'student' and students %}
      <div style="display: flex; align-items: center; gap: 6px;">
        <span style="font-size: 0.75rem; color: var(--text-muted); display: none; @media(min-width: 768px){display:inline;}">Viewing as:</span>
        <select class="student-switcher-select" onchange="window.location.href='{{ url_for('index', view='student') }}&student_id=' + this.value">
          {% for s in students %}
          <option value="{{ s.studentId }}" {% if current_student and current_student.studentId == s.studentId %}selected{% endif %}>
            {{ s.name }} ({{ s.rollNo or s.studentId }})
          </option>
          {% endfor %}
        </select>
      </div>
      {% endif %}

      <!-- Storage Provider Badge -->
      <div class="badge-status" title="Active storage engine">
        <span class="status-dot"></span>
        <span>{{ storage_status.label }}</span>
      </div>

      <!-- Quick Add Student Modal Trigger -->
      <button class="btn-primary" onclick="openModal('addStudentModal')">
        <i class="fa-solid fa-plus"></i>
        <span>New Student</span>
      </button>

      <!-- Theme Switcher -->
      <button class="btn-icon" id="themeToggleBtn" title="Toggle theme">
        <i class="fa-solid fa-moon"></i>
      </button>
    </div>
  </header>

  <main class="app-layout">

    <!-- ========================================== -->
    <!-- VIEW MODE 1: STUDENT PORTAL (FOR STUDENTS) -->
    <!-- ========================================== -->
    {% if view_mode == 'student' and current_student %}

    <!-- Student Hero Banner -->
    <section class="student-hero">
      <div class="hero-profile-info">
        <div class="avatar-wrapper">
          <div class="student-avatar-lg">
            {{ current_student.name[:2].upper() }}
          </div>
          <span class="avatar-badge-active">{{ current_student.status }}</span>
        </div>
        <div class="student-meta">
          <h1>
            {{ current_student.name }}
            <span class="roll-chip">{{ current_student.rollNo }}</span>
          </h1>
          <p style="color: var(--secondary); font-weight: 600; font-size: 0.95rem;">
            {{ current_student.course }} • {{ current_student.department }}
          </p>
          <div class="student-submeta">
            <span><i class="fa-regular fa-envelope"></i> {{ current_student.email }}</span>
            <span><i class="fa-solid fa-phone"></i> {{ current_student.phone }}</span>
            <span><i class="fa-solid fa-calendar-check"></i> {{ current_student.year }} ({{ current_student.semester }})</span>
            <span><i class="fa-solid fa-user-tie"></i> Mentor: {{ current_student.advisor }}</span>
          </div>
        </div>
      </div>

      <div class="hero-actions">
        <button class="btn-secondary" onclick="openModal('idCardModal')">
          <i class="fa-solid fa-id-card"></i> Digital ID Card
        </button>
        {% if current_student.feesDue > 0 %}
        <button class="btn-primary" onclick="openModal('payFeesModal')">
          <i class="fa-solid fa-credit-card"></i> Pay Dues (${{ "%.2f"|format(current_student.feesDue) }})
        </button>
        {% else %}
        <button class="btn-secondary" onclick="openModal('payFeesModal')">
          <i class="fa-solid fa-receipt"></i> Fee Receipts
        </button>
        {% endif %}
        <button class="btn-secondary" onclick="window.print()">
          <i class="fa-solid fa-print"></i> Print Transcript
        </button>
      </div>
    </section>

    <!-- Student Key Metric Stat Cards -->
    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-icon indigo">
          <i class="fa-solid fa-chart-line"></i>
        </div>
        <div class="stat-content">
          <div class="stat-label">Cumulative GPA</div>
          <div class="stat-value">{{ "%.2f"|format(current_student.cgpa) }} <span style="font-size: 0.9rem; color: var(--text-muted);">/ 10</span></div>
          <div class="stat-subtext">
            <span class="pill pill-success" style="font-size: 0.65rem;">Top 5% Dean's List</span>
          </div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon emerald">
          <i class="fa-solid fa-user-check"></i>
        </div>
        <div class="stat-content">
          <div class="stat-label">Overall Attendance</div>
          <div class="stat-value">{{ current_student.attendance }}%</div>
          <div class="stat-subtext">
            {% if current_student.attendance >= 85 %}
            <span class="pill pill-success" style="font-size: 0.65rem;">Excellent Attendance</span>
            {% elif current_student.attendance >= 75 %}
            <span class="pill pill-warning" style="font-size: 0.65rem;">Good (Above 75% Min)</span>
            {% else %}
            <span class="pill pill-danger" style="font-size: 0.65rem;">Attendance Warning!</span>
            {% endif %}
          </div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon cyan">
          <i class="fa-solid fa-book-bookmark"></i>
        </div>
        <div class="stat-content">
          <div class="stat-label">Registered Courses</div>
          <div class="stat-value">{{ current_student.courses|length }} Courses</div>
          <div class="stat-subtext">
            <span class="pill pill-info" style="font-size: 0.65rem;">{{ current_student.courses|sum(attribute='credits') }} Total Credits</span>
          </div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon amber">
          <i class="fa-solid fa-wallet"></i>
        </div>
        <div class="stat-content">
          <div class="stat-label">Semester Fee Ledger</div>
          <div class="stat-value">
            {% if current_student.feesDue == 0 %}
            <span style="color: var(--success);">$0.00</span>
            {% else %}
            <span style="color: var(--warning);">${{ "%.2f"|format(current_student.feesDue) }}</span>
            {% endif %}
          </div>
          <div class="stat-subtext">
            {% if current_student.feesDue == 0 %}
            <span class="pill pill-success" style="font-size: 0.65rem;">Paid in Full</span>
            {% else %}
            <span class="pill pill-warning" style="font-size: 0.65rem;">Pending Due</span>
            {% endif %}
          </div>
        </div>
      </div>
    </div>

    <!-- Student Portal Navigation Tabs -->
    <nav class="portal-tabs">
      <a href="{{ url_for('index', view='student', student_id=current_student.studentId, tab='academics') }}" 
         class="portal-tab-btn {% if active_tab in ['overview', 'academics'] %}active{% endif %}">
        <i class="fa-solid fa-book-open"></i> Enrolled Courses & Electives
      </a>
      <a href="{{ url_for('index', view='student', student_id=current_student.studentId, tab='attendance') }}" 
         class="portal-tab-btn {% if active_tab == 'attendance' %}active{% endif %}">
        <i class="fa-solid fa-calculator"></i> Attendance & Safe-Leave Planner
      </a>
      <a href="{{ url_for('index', view='student', student_id=current_student.studentId, tab='grades') }}" 
         class="portal-tab-btn {% if active_tab == 'grades' %}active{% endif %}">
        <i class="fa-solid fa-award"></i> Grade Report & Transcript
      </a>
      <a href="{{ url_for('index', view='student', student_id=current_student.studentId, tab='timetable') }}" 
         class="portal-tab-btn {% if active_tab == 'timetable' %}active{% endif %}">
        <i class="fa-solid fa-calendar-days"></i> Weekly Timetable
      </a>
      <a href="{{ url_for('index', view='student', student_id=current_student.studentId, tab='fees') }}" 
         class="portal-tab-btn {% if active_tab == 'fees' %}active{% endif %}">
        <i class="fa-solid fa-receipt"></i> Fee Payments & Statement
      </a>
      <a href="{{ url_for('index', view='student', student_id=current_student.studentId, tab='notices') }}" 
         class="portal-tab-btn {% if active_tab == 'notices' %}active{% endif %}">
        <i class="fa-solid fa-bullhorn"></i> Campus Notices
      </a>
    </nav>

    <!-- TAB CONTENT: ACADEMICS & COURSES -->
    {% if active_tab in ['overview', 'academics'] %}
    <div class="two-col-grid">
      <div class="card">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
          <div>
            <h3>Current Registered Courses</h3>
            <p style="font-size: 0.8rem; color: var(--text-muted);">Enrolled curriculum for {{ current_student.semester }}</p>
          </div>
          <button class="btn-primary" onclick="openModal('courseCatalogModal')">
            <i class="fa-solid fa-plus"></i> Add Elective
          </button>
        </div>

        <div class="erp-table-wrapper">
          <table class="erp-table">
            <thead>
              <tr>
                <th>Code</th>
                <th>Course Name</th>
                <th>Credits</th>
                <th>Instructor & Room</th>
                <th>Attendance</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {% for c in current_student.courses %}
              <tr>
                <td><span class="pill pill-purple">{{ c.code }}</span></td>
                <td>
                  <div style="font-weight: 700;">{{ c.name }}</div>
                  <div style="font-size: 0.75rem; color: var(--text-dim);"><i class="fa-regular fa-clock"></i> {{ c.schedule }}</div>
                </td>
                <td><span style="font-weight: 600;">{{ c.credits }} Cr</span></td>
                <td>
                  <div style="font-size: 0.85rem; font-weight: 500;">{{ c.instructor }}</div>
                  <div style="font-size: 0.75rem; color: var(--text-muted);"><i class="fa-solid fa-location-dot"></i> {{ c.room }}</div>
                </td>
                <td style="min-width: 140px;">
                  <div style="display: flex; justify-content: space-between; font-size: 0.75rem; margin-bottom: 3px;">
                    <span>{{ c.classesAttended }}/{{ c.classesTotal }}</span>
                    <span style="font-weight: 700;">{{ c.attendance }}%</span>
                  </div>
                  <div class="progress-track">
                    <div class="progress-fill {% if c.attendance >= 85 %}green{% elif c.attendance >= 75 %}amber{% else %}red{% endif %}" style="width: {{ c.attendance }}%;"></div>
                  </div>
                </td>
                <td>
                  <form method="post" action="{{ url_for('drop_course', student_id=current_student.studentId) }}" onsubmit="return confirm('Drop {{ c.name }}?');">
                    <input type="hidden" name="course_code" value="{{ c.code }}">
                    <button type="submit" class="btn-icon" style="width: 30px; height: 30px; color: var(--danger);" title="Drop Course">
                      <i class="fa-solid fa-trash-can" style="font-size: 0.75rem;"></i>
                    </button>
                  </form>
                </td>
              </tr>
              {% else %}
              <tr><td colspan="6" style="text-align: center; color: var(--text-dim);">No registered courses yet. Click "Add Elective" above.</td></tr>
              {% endfor %}
            </tbody>
          </table>
        </div>
      </div>

      <!-- Right Column: Quick Notices & Academic Advisor -->
      <div style="display: flex; flex-direction: column; gap: 1.5rem;">
        <!-- Advisor Card -->
        <div class="card" style="background: linear-gradient(135deg, rgba(79, 70, 229, 0.08) 0%, var(--bg-surface) 100%);">
          <div style="display: flex; align-items: center; gap: 1rem; margin-bottom: 1rem;">
            <div style="width: 48px; height: 48px; border-radius: 50%; background: var(--bg-surface-elevated); display: flex; align-items: center; justify-content: center; font-size: 1.25rem; color: var(--primary);">
              <i class="fa-solid fa-user-tie"></i>
            </div>
            <div>
              <div style="font-size: 0.75rem; color: var(--text-muted); text-transform: uppercase; font-weight: 600;">Faculty Academic Mentor</div>
              <h4 style="font-size: 1.05rem;">{{ current_student.advisor }}</h4>
              <div style="font-size: 0.78rem; color: var(--secondary);">Department of {{ current_student.department }}</div>
            </div>
          </div>
          <div style="font-size: 0.825rem; color: var(--text-muted); margin-bottom: 1rem;">
            Office Hours: Tuesdays & Thursdays 3:00 PM - 5:00 PM (Room CS-402). Reach out for course advising, petition requests, and career guidance.
          </div>
          <a href="mailto:{{ current_student.advisor|lower|replace(' ', '.')|replace('dr.', '') }}@university.edu" class="btn-secondary" style="width: 100%; justify-content: center;">
            <i class="fa-regular fa-envelope"></i> Send Email to Advisor
          </a>
        </div>

        <!-- Latest Campus Alerts -->
        <div class="card">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
            <h4>Campus Highlights</h4>
            <a href="{{ url_for('index', view='student', student_id=current_student.studentId, tab='notices') }}" style="font-size: 0.75rem; color: var(--primary); text-decoration: none; font-weight: 600;">View All &rarr;</a>
          </div>
          {% for n in notices[:2] %}
          <div class="notice-item">
            <div class="notice-top">
              <span class="pill pill-danger" style="font-size: 0.65rem;">{{ n.priority }}</span>
              <span style="font-size: 0.7rem; color: var(--text-dim);">{{ n.date }}</span>
            </div>
            <div class="notice-title">{{ n.title }}</div>
            <div class="notice-content">{{ n.content[:90] }}...</div>
          </div>
          {% endfor %}
        </div>
      </div>
    </div>
    {% endif %}

    <!-- TAB CONTENT: ATTENDANCE & SAFE LEAVE CALCULATOR -->
    {% if active_tab == 'attendance' %}
    <div class="two-col-grid">
      <!-- Left: Subject-wise breakdown -->
      <div class="card">
        <h3>Subject Attendance Analysis</h3>
        <p style="font-size: 0.8rem; color: var(--text-muted); margin-bottom: 1rem;">Minimum 75% attendance is required to appear for semester examinations.</p>
        
        <div class="erp-table-wrapper">
          <table class="erp-table">
            <thead>
              <tr>
                <th>Subject</th>
                <th>Conducted</th>
                <th>Attended</th>
                <th>Absent</th>
                <th>Percentage</th>
                <th>Quick Log</th>
              </tr>
            </thead>
            <tbody>
              {% for c in current_student.courses %}
              <tr>
                <td>
                  <div style="font-weight: 700;">{{ c.name }}</div>
                  <span class="pill pill-purple" style="font-size: 0.65rem;">{{ c.code }}</span>
                </td>
                <td><b>{{ c.classesTotal }}</b></td>
                <td><b style="color: var(--success);">{{ c.classesAttended }}</b></td>
                <td><b style="color: var(--danger);">{{ c.classesTotal - c.classesAttended }}</b></td>
                <td style="min-width: 140px;">
                  <div style="display: flex; justify-content: space-between; font-size: 0.75rem; margin-bottom: 3px;">
                    <span style="font-weight: 700;">{{ c.attendance }}%</span>
                    {% if c.attendance >= 85 %}
                    <span style="color: var(--success); font-weight: 600;">Safe</span>
                    {% elif c.attendance >= 75 %}
                    <span style="color: var(--warning); font-weight: 600;">Borderline</span>
                    {% else %}
                    <span style="color: var(--danger); font-weight: 600;">Critical</span>
                    {% endif %}
                  </div>
                  <div class="progress-track">
                    <div class="progress-fill {% if c.attendance >= 85 %}green{% elif c.attendance >= 75 %}amber{% else %}red{% endif %}" style="width: {{ c.attendance }}%;"></div>
                  </div>
                </td>
                <td>
                  <div style="display: flex; gap: 4px;">
                    <form method="post" action="{{ url_for('attendance_action', student_id=current_student.studentId) }}">
                      <input type="hidden" name="course_code" value="{{ c.code }}">
                      <input type="hidden" name="action_type" value="attend">
                      <button type="submit" class="btn-icon" style="width: 28px; height: 28px; color: var(--success);" title="Mark +1 Attended">
                        <i class="fa-solid fa-check"></i>
                      </button>
                    </form>
                    <form method="post" action="{{ url_for('attendance_action', student_id=current_student.studentId) }}">
                      <input type="hidden" name="course_code" value="{{ c.code }}">
                      <input type="hidden" name="action_type" value="miss">
                      <button type="submit" class="btn-icon" style="width: 28px; height: 28px; color: var(--danger);" title="Mark +1 Absent">
                        <i class="fa-solid fa-xmark"></i>
                      </button>
                    </form>
                  </div>
                </td>
              </tr>
              {% endfor %}
            </tbody>
          </table>
        </div>
      </div>

      <!-- Right: Interactive Bunk & Safe Leave Calculator -->
      <div class="bunk-calculator">
        <div style="display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.75rem;">
          <div style="width: 40px; height: 40px; border-radius: 10px; background: rgba(99, 102, 241, 0.2); color: #818cf8; display: flex; align-items: center; justify-content: center; font-size: 1.2rem;">
            <i class="fa-solid fa-calculator"></i>
          </div>
          <div>
            <h3>Smart Safe-Leave Planner</h3>
            <p style="font-size: 0.75rem; color: var(--text-muted);">Real-time attendance buffer forecasting</p>
          </div>
        </div>

        <p style="font-size: 0.825rem; color: var(--text-muted);">
          Calculate exactly how many upcoming lectures you can safely skip while staying compliant, or how many you must attend to recover!
        </p>

        <div class="calc-slider-box">
          <div style="display: flex; justify-content: space-between; font-size: 0.85rem; font-weight: 600; margin-bottom: 0.5rem;">
            <span>Target Minimum Attendance:</span>
            <span id="targetPercentDisplay" style="color: var(--secondary);">75%</span>
          </div>
          <input type="range" id="targetSlider" min="65" max="95" value="75" oninput="updateBunkCalc(this.value)">
        </div>

        <div id="bunkResultCard" class="calc-result-box">
          <div id="bunkResultIcon" class="calc-result-icon safe">
            <i class="fa-solid fa-umbrella-beach"></i>
          </div>
          <div id="bunkResultText">
            <div style="font-weight: 700; font-size: 0.95rem; color: var(--text-main);" id="bunkHeading">Calculating safe buffer...</div>
            <div style="font-size: 0.8rem; color: var(--text-muted);" id="bunkSubtext">Loading student stats...</div>
          </div>
        </div>

        <div style="margin-top: 1.25rem; font-size: 0.78rem; color: var(--text-dim); background: rgba(0,0,0,0.2); padding: 10px; border-radius: 8px;">
          <i class="fa-solid fa-circle-info"></i> University Ordinance requires minimum 75% attendance across all registered courses to appear in End-Semester Exams without medical concession.
        </div>
      </div>
    </div>
    {% endif %}

    <!-- TAB CONTENT: GRADES & TRANSCRIPT -->
    {% if active_tab == 'grades' %}
    <div class="card">
      <div style="display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; margin-bottom: 1.25rem; gap: 1rem;">
        <div>
          <h3>Official Semester Grade Sheet</h3>
          <p style="font-size: 0.825rem; color: var(--text-muted);">Academic Transcript Record for {{ current_student.semester }} (Session 2026)</p>
        </div>
        <div style="display: flex; gap: 0.75rem;">
          <button class="btn-secondary" onclick="window.print()">
            <i class="fa-solid fa-print"></i> Print Transcript
          </button>
        </div>
      </div>

      <div class="erp-table-wrapper">
        <table class="erp-table">
          <thead>
            <tr>
              <th>Course Code</th>
              <th>Subject / Title</th>
              <th>Credit Hours</th>
              <th>Letter Grade</th>
              <th>Grade Points</th>
              <th>Evaluation Status</th>
            </tr>
          </thead>
          <tbody>
            {% for g in current_student.grades %}
            <tr>
              <td><span class="pill pill-purple">{{ g.code }}</span></td>
              <td><b style="font-size: 0.9rem;">{{ g.name }}</b></td>
              <td><b>{{ g.credits }}</b></td>
              <td>
                <span class="pill {% if g.grade in ['O', 'A+', 'A'] %}pill-success{% elif g.grade in ['A-', 'B+'] %}pill-info{% else %}pill-warning{% endif %}" style="font-weight: 800; font-size: 0.85rem;">
                  {{ g.grade }}
                </span>
              </td>
              <td><b style="color: var(--secondary);">{{ g.points }} / 10</b></td>
              <td><span class="pill pill-success"><i class="fa-solid fa-check"></i> {{ g.status }}</span></td>
            </tr>
            {% endfor %}
          </tbody>
          <tfoot>
            <tr style="background: var(--bg-surface-elevated); font-weight: 700;">
              <td colspan="2">TOTAL CREDITS COMPLETED: {{ current_student.grades|sum(attribute='credits') }}</td>
              <td>{{ current_student.grades|sum(attribute='credits') }} Cr</td>
              <td colspan="2">CUMULATIVE GPA (CGPA): <span style="color: var(--primary); font-size: 1.1rem;">{{ "%.2f"|format(current_student.cgpa) }}</span> / 10.0</td>
              <td><span class="pill pill-success">QUALIFIED (FIRST CLASS WITH DISTINCTION)</span></td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
    {% endif %}

    <!-- TAB CONTENT: WEEKLY TIMETABLE -->
    {% if active_tab == 'timetable' %}
    <div class="card">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.25rem;">
        <div>
          <h3>Weekly Academic Timetable</h3>
          <p style="font-size: 0.8rem; color: var(--text-muted);">Synchronized schedule for lectures, labs, and tutorials</p>
        </div>
        <span class="pill pill-info"><i class="fa-regular fa-clock"></i> Active Semester Schedule</span>
      </div>

      <div class="timetable-grid">
        {% for day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'] %}
        <div class="timetable-day-col">
          <div class="day-header">
            <span>{{ day }}</span>
            <span style="font-size: 0.7rem; color: var(--text-dim);"><i class="fa-solid fa-book"></i></span>
          </div>
          {% for slot in current_student.timetable %}
          {% if slot.day == day %}
          <div class="class-slot-card">
            <div class="class-time"><i class="fa-regular fa-clock"></i> {{ slot.time }}</div>
            <div class="class-title">{{ slot.course }}</div>
            <div class="class-room"><i class="fa-solid fa-location-dot"></i> {{ slot.room }} • {{ slot.instructor }}</div>
          </div>
          {% endif %}
          {% endfor %}
        </div>
        {% endfor %}
      </div>
    </div>
    {% endif %}

    <!-- TAB CONTENT: FEES & FINANCIAL LEDGER -->
    {% if active_tab == 'fees' %}
    <div class="two-col-grid">
      <!-- Statement Card -->
      <div class="card">
        <h3>Semester Financial Statement</h3>
        <p style="font-size: 0.8rem; color: var(--text-muted); margin-bottom: 1.25rem;">Itemized billing ledger for {{ current_student.semester }}</p>

        <div class="erp-table-wrapper" style="margin-bottom: 1.5rem;">
          <table class="erp-table">
            <thead>
              <tr>
                <th>Fee Component</th>
                <th>Amount</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Academic Tuition & Instruction Fee</td>
                <td>$3,500.00</td>
                <td><span class="pill pill-success">Billed</span></td>
              </tr>
              <tr>
                <td>Computing, Cloud & Engineering Labs</td>
                <td>$500.00</td>
                <td><span class="pill pill-success">Billed</span></td>
              </tr>
              <tr>
                <td>Campus Library, E-Resources & Student Union</td>
                <td>$300.00</td>
                <td><span class="pill pill-success">Billed</span></td>
              </tr>
              <tr>
                <td>Examination & Evaluation Assessment</td>
                <td>$200.00</td>
                <td><span class="pill pill-success">Billed</span></td>
              </tr>
              <tr style="background: var(--bg-surface-elevated); font-weight: 700;">
                <td>TOTAL SEMESTER DUES</td>
                <td>${{ "%.2f"|format(current_student.feesTotal) }}</td>
                <td>
                  <span class="pill {% if current_student.feesStatus == 'Paid' %}pill-success{% elif current_student.feesStatus == 'Partial' %}pill-warning{% else %}pill-danger{% endif %}">
                    {{ current_student.feesStatus }}
                  </span>
                </td>
              </tr>
              <tr>
                <td>TOTAL AMOUNT PAID</td>
                <td style="color: var(--success); font-weight: 700;">${{ "%.2f"|format(current_student.feesPaid) }}</td>
                <td><i class="fa-solid fa-check-double" style="color: var(--success);"></i> Received</td>
              </tr>
              <tr style="font-weight: 800; font-size: 1rem;">
                <td>REMAINING BALANCE DUE</td>
                <td style="color: {% if current_student.feesDue > 0 %}var(--danger){% else %}var(--success){% endif %};">
                  ${{ "%.2f"|format(current_student.feesDue) }}
                </td>
                <td>
                  {% if current_student.feesDue > 0 %}
                  <button class="btn-primary" style="padding: 4px 12px; font-size: 0.78rem;" onclick="openModal('payFeesModal')">
                    Pay Now
                  </button>
                  {% else %}
                  <span class="pill pill-success">Fully Cleared</span>
                  {% endif %}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <h4>Payment Transaction History</h4>
        <div class="erp-table-wrapper" style="margin-top: 0.75rem;">
          <table class="erp-table">
            <thead>
              <tr>
                <th>Receipt ID</th>
                <th>Date</th>
                <th>Amount</th>
                <th>Payment Channel</th>
                <th>Receipt</th>
              </tr>
            </thead>
            <tbody>
              {% for p in current_student.payments %}
              <tr>
                <td><span class="pill pill-purple">{{ p.receiptId }}</span></td>
                <td>{{ p.date }}</td>
                <td><b style="color: var(--success);">${{ "%.2f"|format(p.amount) }}</b></td>
                <td>{{ p.method }}</td>
                <td>
                  <button class="btn-secondary" style="padding: 3px 8px; font-size: 0.75rem;" onclick="viewReceiptModal('{{ p.receiptId }}', '{{ p.date }}', '{{ p.amount }}', '{{ p.method }}')">
                    <i class="fa-solid fa-receipt"></i> View Receipt
                  </button>
                </td>
              </tr>
              {% else %}
              <tr><td colspan="5" style="text-align: center; color: var(--text-dim);">No payment transactions recorded yet.</td></tr>
              {% endfor %}
            </tbody>
          </table>
        </div>
      </div>

      <!-- Quick Payment Portal Box -->
      <div class="card" style="background: linear-gradient(135deg, rgba(79, 70, 229, 0.08) 0%, var(--bg-surface) 100%);">
        <h3>Online Fee Clearance</h3>
        <p style="font-size: 0.8rem; color: var(--text-muted); margin-bottom: 1.25rem;">Secure instant payment processing with automated invoice generation.</p>
        
        <form method="post" action="{{ url_for('pay_fees', student_id=current_student.studentId) }}">
          <div class="form-group">
            <label class="form-label">Paying For Student</label>
            <input class="form-control" value="{{ current_student.name }} ({{ current_student.rollNo }})" readonly>
          </div>
          <div class="form-group">
            <label class="form-label">Amount to Pay ($ USD)</label>
            <input type="number" step="0.01" min="1" max="{{ current_student.feesDue if current_student.feesDue > 0 else 5000 }}" 
                   name="amount" class="form-control" value="{{ current_student.feesDue if current_student.feesDue > 0 else 500 }}" required>
          </div>
          <div class="form-group">
            <label class="form-label">Payment Channel</label>
            <select name="method" class="form-control">
              <option value="Debit / Credit Card (Visa/Mastercard)">Debit / Credit Card (Visa/Mastercard)</option>
              <option value="Direct University Bank Transfer">Direct University Bank Transfer</option>
              <option value="Campus Bursar Wire / ACH">Campus Bursar Wire / ACH</option>
              <option value="Digital Campus Wallet">Digital Campus Wallet</option>
            </select>
          </div>
          <button type="submit" class="btn-primary" style="width: 100%; justify-content: center; padding: 12px;">
            <i class="fa-solid fa-lock"></i> Process Payment & Generate Receipt
          </button>
        </form>
      </div>
    </div>
    {% endif %}

    <!-- TAB CONTENT: CAMPUS NOTICES -->
    {% if active_tab == 'notices' %}
    <div class="card">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.25rem;">
        <div>
          <h3>University Bulletin & Official Notices</h3>
          <p style="font-size: 0.8rem; color: var(--text-muted);">Stay updated with university announcements, examinations, and recruitment drives.</p>
        </div>
      </div>

      {% for n in notices %}
      <div class="notice-item" style="padding: 1.25rem;">
        <div class="notice-top">
          <div style="display: flex; align-items: center; gap: 8px;">
            <span class="pill {% if n.priority == 'Urgent' %}pill-danger{% elif n.priority == 'High' %}pill-warning{% else %}pill-info{% endif %}">
              {{ n.priority }}
            </span>
            <span class="pill pill-purple">{{ n.category }}</span>
          </div>
          <span style="font-size: 0.78rem; color: var(--text-dim);"><i class="fa-regular fa-calendar"></i> {{ n.date }}</span>
        </div>
        <div class="notice-title" style="font-size: 1.1rem; margin-top: 6px;">{{ n.title }}</div>
        <div class="notice-content" style="font-size: 0.875rem; margin: 8px 0;">{{ n.content }}</div>
        <div class="notice-meta">
          <span><i class="fa-solid fa-bullhorn"></i> Issued by: <b>{{ n.author }}</b></span>
          <span><i class="fa-solid fa-shield-halved"></i> Verified Campus Notice</span>
        </div>
      </div>
      {% endfor %}
    </div>
    {% endif %}

    {% endif %}
    <!-- END VIEW MODE 1 -->


    <!-- ========================================== -->
    <!-- VIEW MODE 2: FACULTY & ADMIN ERP VIEW     -->
    <!-- ========================================== -->
    {% if view_mode == 'admin' %}

    <!-- Institutional KPI Overview -->
    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-icon indigo">
          <i class="fa-solid fa-users"></i>
        </div>
        <div class="stat-content">
          <div class="stat-label">Total Registered Students</div>
          <div class="stat-value">{{ stats.total_students }}</div>
          <div class="stat-subtext">Active enrollment across all faculties</div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon cyan">
          <i class="fa-solid fa-graduation-cap"></i>
        </div>
        <div class="stat-content">
          <div class="stat-label">Institutional Avg CGPA</div>
          <div class="stat-value">{{ stats.avg_cgpa }} <span style="font-size: 0.85rem; color: var(--text-muted);">/ 10.0</span></div>
          <div class="stat-subtext">Cumulative academic standard</div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon emerald">
          <i class="fa-solid fa-clipboard-user"></i>
        </div>
        <div class="stat-content">
          <div class="stat-label">Avg Attendance Ratio</div>
          <div class="stat-value">{{ stats.avg_attendance }}%</div>
          <div class="stat-subtext">
            <span class="pill pill-success" style="font-size: 0.65rem;">{{ stats.excellent_att }} Good</span>
            <span class="pill pill-danger" style="font-size: 0.65rem;">{{ stats.critical_att }} &lt;75%</span>
          </div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon amber">
          <i class="fa-solid fa-hand-holding-dollar"></i>
        </div>
        <div class="stat-content">
          <div class="stat-label">Total Outstanding Dues</div>
          <div class="stat-value">${{ "%.2f"|format(stats.total_dues) }}</div>
          <div class="stat-subtext">Collected: ${{ "%.2f"|format(stats.total_paid) }}</div>
        </div>
      </div>
    </div>

    <!-- Quick Add Student Bar (Full Backward Compatibility for Minimal Form & Tests) -->
    <div class="card" style="padding: 1.25rem;">
      <div style="font-weight: 700; font-size: 0.95rem; margin-bottom: 0.75rem; display: flex; align-items: center; justify-content: space-between;">
        <span><i class="fa-solid fa-bolt" style="color: var(--warning);"></i> Fast Student Registration Bar</span>
        <button class="btn-secondary" style="font-size: 0.75rem; padding: 4px 10px;" onclick="openModal('addStudentModal')">
          <i class="fa-solid fa-sliders"></i> Open Detailed Registration Form
        </button>
      </div>
      <form method="post" action="{{ url_for('add_student') }}" class="quick-add-bar" style="margin-bottom: 0;">
        <input type="hidden" name="view" value="admin">
        <input name="name" class="form-control" placeholder="Student name (e.g. Samarth)" required>
        <input name="course" class="form-control" placeholder="Course/Program (e.g. Cloud Computing)" required>
        <input name="email" class="form-control" placeholder="University Email" type="email" required>
        <button type="submit" class="btn-primary" style="white-space: nowrap;">
          <i class="fa-solid fa-user-plus"></i> Add Student
        </button>
      </form>
    </div>

    <!-- Student Management Roster Table Card -->
    <div class="card">
      <!-- Toolbar: Search, Filters & Exports -->
      <div class="table-toolbar">
        <div class="search-box">
          <i class="fa-solid fa-magnifying-glass"></i>
          <input type="text" id="studentSearchInput" class="form-control" placeholder="Search by name, roll no, email, or dept..." onkeyup="filterStudentTable()">
        </div>

        <div class="filter-actions">
          <select id="departmentFilter" class="form-control" style="width: auto;" onchange="filterStudentTable()">
            <option value="">All Departments</option>
            <option value="Computer Science">Computer Science</option>
            <option value="AI & Machine Learning">AI & Machine Learning</option>
            <option value="Electrical">Electrical & Electronics</option>
            <option value="Business">Business & Management</option>
          </select>

          <select id="attendanceFilter" class="form-control" style="width: auto;" onchange="filterStudentTable()">
            <option value="">All Attendance</option>
            <option value="above75">Compliant (>= 75%)</option>
            <option value="below75">Critical (&lt; 75%)</option>
          </select>

          <a href="{{ url_for('export_csv') }}" class="btn-secondary" title="Export as CSV spreadsheet">
            <i class="fa-solid fa-file-csv"></i> CSV
          </a>
          <a href="{{ url_for('export_json') }}" class="btn-secondary" title="Export as JSON">
            <i class="fa-solid fa-file-code"></i> JSON
          </a>
          <form method="post" action="{{ url_for('reset_data') }}" style="display: inline;" onsubmit="return confirm('Reset database to pristine sample data?');">
            <button type="submit" class="btn-secondary" title="Reset sample records">
              <i class="fa-solid fa-rotate-left"></i> Reset
            </button>
          </form>
        </div>
      </div>

      <!-- Main Student Directory Table -->
      <div class="erp-table-wrapper">
        <table class="erp-table" id="studentsTable">
          <thead>
            <tr>
              <th>Student ID & Roll No</th>
              <th>Student Name & Email</th>
              <th>Course & Department</th>
              <th>Semester</th>
              <th>CGPA</th>
              <th>Attendance</th>
              <th>Fee Status</th>
              <th style="text-align: right;">Actions</th>
            </tr>
          </thead>
          <tbody>
            {% for s in students %}
            <tr data-name="{{ s.name|lower }}" data-roll="{{ s.rollNo|lower }}" data-email="{{ s.email|lower }}" data-dept="{{ s.department|lower }}" data-att="{{ s.attendance }}">
              <td>
                <span class="pill pill-purple" style="font-family: monospace;">{{ s.studentId }}</span>
                <div style="font-size: 0.75rem; color: var(--text-dim); margin-top: 2px;">{{ s.rollNo }}</div>
              </td>
              <td>
                <div style="display: flex; align-items: center; gap: 10px;">
                  <div style="width: 36px; height: 36px; border-radius: 10px; background: linear-gradient(135deg, #4f46e5 0%, #06b6d4 100%); color: #fff; display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 0.85rem;">
                    {{ s.name[:2].upper() }}
                  </div>
                  <div>
                    <a href="{{ url_for('index', view='student', student_id=s.studentId) }}" style="font-weight: 700; color: var(--text-main); text-decoration: none;">
                      {{ s.name }}
                    </a>
                    <div style="font-size: 0.75rem; color: var(--text-dim);">{{ s.email }}</div>
                  </div>
                </div>
              </td>
              <td>
                <div style="font-weight: 600;">{{ s.course }}</div>
                <div style="font-size: 0.75rem; color: var(--text-muted);">{{ s.department }}</div>
              </td>
              <td>
                <span class="pill pill-info">{{ s.semester }}</span>
                <div style="font-size: 0.72rem; color: var(--text-dim); margin-top: 2px;">{{ s.year }}</div>
              </td>
              <td>
                <span style="font-weight: 800; font-size: 0.95rem; color: var(--primary);">{{ "%.2f"|format(s.cgpa) }}</span>
              </td>
              <td style="min-width: 130px;">
                <div style="display: flex; justify-content: space-between; font-size: 0.75rem; margin-bottom: 2px;">
                  <span style="font-weight: 700;">{{ s.attendance }}%</span>
                  {% if s.attendance < 75 %}
                  <span style="color: var(--danger); font-size: 0.65rem;">Defaulter</span>
                  {% endif %}
                </div>
                <div class="progress-track">
                  <div class="progress-fill {% if s.attendance >= 85 %}green{% elif s.attendance >= 75 %}amber{% else %}red{% endif %}" style="width: {{ s.attendance }}%;"></div>
                </div>
              </td>
              <td>
                {% if s.feesStatus == 'Paid' %}
                <span class="pill pill-success"><i class="fa-solid fa-check"></i> Paid</span>
                {% elif s.feesStatus == 'Partial' %}
                <span class="pill pill-warning">${{ "%.0f"|format(s.feesDue) }} Due</span>
                {% else %}
                <span class="pill pill-danger">Unpaid</span>
                {% endif %}
              </td>
              <td style="text-align: right;">
                <div style="display: inline-flex; gap: 6px;">
                  <a href="{{ url_for('index', view='student', student_id=s.studentId) }}" class="btn-icon" style="width: 32px; height: 32px;" title="Switch to Student Portal View">
                    <i class="fa-solid fa-arrow-up-right-from-square" style="font-size: 0.8rem;"></i>
                  </a>
                  <button class="btn-icon" style="width: 32px; height: 32px;" title="Edit Student Details"
                          onclick="openEditModal('{{ s.studentId }}', '{{ s.name }}', '{{ s.course }}', '{{ s.email }}', '{{ s.rollNo }}', '{{ s.department }}', '{{ s.year }}', '{{ s.semester }}', '{{ s.phone }}', '{{ s.cgpa }}', '{{ s.attendance }}', '{{ s.feesTotal }}', '{{ s.feesPaid }}')">
                    <i class="fa-solid fa-pen" style="font-size: 0.8rem;"></i>
                  </button>
                  <form method="post" action="{{ url_for('delete_student', student_id=s.studentId) }}" onsubmit="return confirm('Permanently delete record for {{ s.name }}?');" style="display: inline;">
                    <button type="submit" class="btn-icon" style="width: 32px; height: 32px; color: var(--danger);" title="Delete Student">
                      <i class="fa-solid fa-trash-can" style="font-size: 0.8rem;"></i>
                    </button>
                  </form>
                </div>
              </td>
            </tr>
            {% else %}
            <tr><td colspan="8" style="text-align: center; color: var(--text-dim);">No student records found. Add one above!</td></tr>
            {% endfor %}
          </tbody>
        </table>
      </div>
    </div>

    {% endif %}
    <!-- END VIEW MODE 2 -->

    <!-- System Footer with Required Deployment Info -->
    <footer class="footer">
      <div>
        <span>Served by instance/host: <b>{{ host }}</b></span>
        <span style="margin: 0 8px;">•</span>
        <span>Total records: <b>{{ students|length }}</b></span>
        <span style="margin: 0 8px;">•</span>
        <span>Storage: <b>{{ storage_status.label }}</b></span>
      </div>
      <div>
        <span>AuraCampus Enterprise SIS • High-Availability Cloud Architecture</span>
      </div>
    </footer>

  </main>

  <!-- ========================================== -->
  <!-- MODALS                                     -->
  <!-- ========================================== -->

  <!-- Modal 1: Detailed Add Student Modal -->
  <div class="modal-backdrop" id="addStudentModal">
    <div class="modal-window">
      <div class="modal-header">
        <h3><i class="fa-solid fa-user-plus" style="color: var(--primary);"></i> Register New Student</h3>
        <button class="btn-icon" onclick="closeModal('addStudentModal')"><i class="fa-solid fa-xmark"></i></button>
      </div>
      <form method="post" action="{{ url_for('add_student') }}">
        <input type="hidden" name="view" value="{{ view_mode }}">
        <div class="form-grid">
          <div class="form-group">
            <label class="form-label">Full Name *</label>
            <input name="name" class="form-control" placeholder="e.g. Samarth Sharma" required>
          </div>
          <div class="form-group">
            <label class="form-label">University Email *</label>
            <input name="email" type="email" class="form-control" placeholder="student@university.edu" required>
          </div>
          <div class="form-group">
            <label class="form-label">Primary Degree / Course *</label>
            <input name="course" class="form-control" placeholder="e.g. Cloud Computing" required>
          </div>
          <div class="form-group">
            <label class="form-label">Department *</label>
            <select name="department" class="form-control">
              <option value="Computer Science & Engineering">Computer Science & Engineering</option>
              <option value="AI & Machine Learning">AI & Machine Learning</option>
              <option value="Electrical & Electronics">Electrical & Electronics</option>
              <option value="Mechanical Engineering">Mechanical Engineering</option>
              <option value="Business & Management">Business & Management</option>
            </select>
          </div>
          <div class="form-group">
            <label class="form-label">Roll Number</label>
            <input name="rollNo" class="form-control" placeholder="e.g. 2026CSB1042">
          </div>
          <div class="form-group">
            <label class="form-label">Contact Phone</label>
            <input name="phone" class="form-control" placeholder="+1 (555) 234-5678">
          </div>
          <div class="form-group">
            <label class="form-label">Academic Year</label>
            <select name="year" class="form-control">
              <option value="1st Year">1st Year (Freshman)</option>
              <option value="2nd Year">2nd Year (Sophomore)</option>
              <option value="3rd Year" selected>3rd Year (Junior)</option>
              <option value="4th Year">4th Year (Senior)</option>
            </select>
          </div>
          <div class="form-group">
            <label class="form-label">Current Semester</label>
            <select name="semester" class="form-control">
              <option value="Semester 1">Semester 1</option>
              <option value="Semester 2">Semester 2</option>
              <option value="Semester 3">Semester 3</option>
              <option value="Semester 4">Semester 4</option>
              <option value="Semester 5">Semester 5</option>
              <option value="Semester 6" selected>Semester 6</option>
              <option value="Semester 7">Semester 7</option>
              <option value="Semester 8">Semester 8</option>
            </select>
          </div>
          <div class="form-group">
            <label class="form-label">Initial CGPA (out of 10)</label>
            <input name="cgpa" type="number" step="0.01" min="0" max="10" class="form-control" value="8.50">
          </div>
          <div class="form-group">
            <label class="form-label">Initial Attendance %</label>
            <input name="attendance" type="number" step="0.1" min="0" max="100" class="form-control" value="88.0">
          </div>
          <div class="form-group">
            <label class="form-label">Semester Fee Total ($)</label>
            <input name="feesTotal" type="number" step="0.01" class="form-control" value="4500.00">
          </div>
          <div class="form-group">
            <label class="form-label">Fee Amount Paid ($)</label>
            <input name="feesPaid" type="number" step="0.01" class="form-control" value="4500.00">
          </div>
          <div class="form-group full-width">
            <label class="form-label">Academic Advisor</label>
            <input name="advisor" class="form-control" value="Prof. Alan Vance">
          </div>
        </div>
        <div style="margin-top: 1.25rem; display: flex; justify-content: flex-end; gap: 0.75rem;">
          <button type="button" class="btn-secondary" onclick="closeModal('addStudentModal')">Cancel</button>
          <button type="submit" class="btn-primary"><i class="fa-solid fa-check"></i> Register Student</button>
        </div>
      </form>
    </div>
  </div>

  <!-- Modal 2: Edit Student Details Modal -->
  <div class="modal-backdrop" id="editStudentModal">
    <div class="modal-window">
      <div class="modal-header">
        <h3><i class="fa-solid fa-pen-to-square" style="color: var(--primary);"></i> Edit Student Information</h3>
        <button class="btn-icon" onclick="closeModal('editStudentModal')"><i class="fa-solid fa-xmark"></i></button>
      </div>
      <form id="editStudentForm" method="post" action="">
        <input type="hidden" name="view" value="{{ view_mode }}">
        <div class="form-grid">
          <div class="form-group">
            <label class="form-label">Full Name</label>
            <input id="edit_name" name="name" class="form-control" required>
          </div>
          <div class="form-group">
            <label class="form-label">University Email</label>
            <input id="edit_email" name="email" type="email" class="form-control" required>
          </div>
          <div class="form-group">
            <label class="form-label">Course / Degree</label>
            <input id="edit_course" name="course" class="form-control" required>
          </div>
          <div class="form-group">
            <label class="form-label">Department</label>
            <input id="edit_dept" name="department" class="form-control" required>
          </div>
          <div class="form-group">
            <label class="form-label">Roll Number</label>
            <input id="edit_roll" name="rollNo" class="form-control">
          </div>
          <div class="form-group">
            <label class="form-label">Phone</label>
            <input id="edit_phone" name="phone" class="form-control">
          </div>
          <div class="form-group">
            <label class="form-label">Year</label>
            <input id="edit_year" name="year" class="form-control">
          </div>
          <div class="form-group">
            <label class="form-label">Semester</label>
            <input id="edit_sem" name="semester" class="form-control">
          </div>
          <div class="form-group">
            <label class="form-label">CGPA</label>
            <input id="edit_cgpa" name="cgpa" type="number" step="0.01" class="form-control">
          </div>
          <div class="form-group">
            <label class="form-label">Attendance %</label>
            <input id="edit_attendance" name="attendance" type="number" step="0.1" class="form-control">
          </div>
          <div class="form-group">
            <label class="form-label">Fee Total ($)</label>
            <input id="edit_feesTotal" name="feesTotal" type="number" step="0.01" class="form-control">
          </div>
          <div class="form-group">
            <label class="form-label">Fee Paid ($)</label>
            <input id="edit_feesPaid" name="feesPaid" type="number" step="0.01" class="form-control">
          </div>
        </div>
        <div style="margin-top: 1.25rem; display: flex; justify-content: flex-end; gap: 0.75rem;">
          <button type="button" class="btn-secondary" onclick="closeModal('editStudentModal')">Cancel</button>
          <button type="submit" class="btn-primary"><i class="fa-solid fa-save"></i> Save Changes</button>
        </div>
      </form>
    </div>
  </div>

  <!-- Modal 3: Digital Student ID Card Modal -->
  {% if current_student %}
  <div class="modal-backdrop" id="idCardModal">
    <div class="modal-window" style="max-width: 500px; background: transparent; border: none; box-shadow: none;">
      <div style="display: flex; justify-content: flex-end; margin-bottom: 0.5rem;">
        <button class="btn-icon" style="background: rgba(0,0,0,0.6); color: white;" onclick="closeModal('idCardModal')">
          <i class="fa-solid fa-xmark"></i>
        </button>
      </div>

      <div class="id-card-container">
        <div class="id-card">
          <div class="id-card-header">
            <div>
              <div class="id-university-name">AURACAMPUS UNIVERSITY</div>
              <div style="font-size: 0.68rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.1em;">Official Smart Student Identity</div>
            </div>
            <div style="width: 32px; height: 32px; border-radius: 8px; background: rgba(255, 255, 255, 0.1); display: flex; align-items: center; justify-content: center; font-size: 1rem; color: var(--secondary);">
              <i class="fa-solid fa-microchip"></i>
            </div>
          </div>

          <div class="id-card-body">
            <div class="id-photo">
              {{ current_student.name[:2].upper() }}
            </div>
            <div class="id-details">
              <div class="id-student-name">{{ current_student.name }}</div>
              <div class="id-field-row">
                <span>Student ID:</span>
                <span class="id-field-val" style="color: var(--secondary); font-family: monospace;">{{ current_student.studentId }}</span>
              </div>
              <div class="id-field-row">
                <span>Roll No:</span>
                <span class="id-field-val">{{ current_student.rollNo }}</span>
              </div>
              <div class="id-field-row">
                <span>Program:</span>
                <span class="id-field-val">{{ current_student.course }}</span>
              </div>
              <div class="id-field-row">
                <span>Department:</span>
                <span class="id-field-val">{{ current_student.department }}</span>
              </div>
              <div class="id-field-row">
                <span>Validity:</span>
                <span class="id-field-val" style="color: #34d399;">2024 — 2028</span>
              </div>
            </div>
          </div>

          <div class="id-card-footer">
            <div class="barcode-simulation">|||||| || | |||| ||| |||</div>
            <div style="font-size: 0.72rem; color: #94a3b8; text-align: right;">
              <div>Status: <span style="color: #34d399; font-weight: 700;">ACTIVE</span></div>
              <div style="font-size: 0.65rem;">Auth Token: SIS-{{ current_student.studentId }}</div>
            </div>
          </div>
        </div>
      </div>

      <div style="display: flex; justify-content: center; margin-top: 1.25rem;">
        <button class="btn-primary" onclick="window.print()">
          <i class="fa-solid fa-download"></i> Save / Print ID Card
        </button>
      </div>
    </div>
  </div>
  {% endif %}

  <!-- Modal 4: Electives Course Catalog Registration Modal -->
  {% if current_student %}
  <div class="modal-backdrop" id="courseCatalogModal">
    <div class="modal-window" style="max-width: 650px;">
      <div class="modal-header">
        <h3><i class="fa-solid fa-plus-circle" style="color: var(--primary);"></i> Register Elective Course</h3>
        <button class="btn-icon" onclick="closeModal('courseCatalogModal')"><i class="fa-solid fa-xmark"></i></button>
      </div>
      <p style="font-size: 0.825rem; color: var(--text-muted); margin-bottom: 1rem;">
        Select from available approved department electives for {{ current_student.semester }}:
      </p>

      <div style="display: flex; flex-direction: column; gap: 0.75rem;">
        {% for course in courses %}
        <div style="background: var(--bg-surface-elevated); border: 1px solid var(--border-subtle); border-radius: 12px; padding: 1rem; display: flex; justify-content: space-between; align-items: center; gap: 1rem;">
          <div>
            <div style="display: flex; align-items: center; gap: 6px;">
              <span class="pill pill-purple">{{ course.code }}</span>
              <span style="font-weight: 700; font-size: 0.95rem;">{{ course.name }}</span>
            </div>
            <div style="font-size: 0.78rem; color: var(--text-muted); margin-top: 3px;">
              Instructor: <b>{{ course.instructor }}</b> • Schedule: {{ course.schedule }} • Room: {{ course.room }}
            </div>
            <div style="font-size: 0.72rem; color: var(--secondary); margin-top: 2px;">
              {{ course.department }} • {{ course.credits }} Academic Credits
            </div>
          </div>
          <form method="post" action="{{ url_for('enroll_course', student_id=current_student.studentId) }}">
            <input type="hidden" name="course_code" value="{{ course.code }}">
            <button type="submit" class="btn-primary" style="white-space: nowrap; padding: 6px 14px; font-size: 0.8rem;">
              Enroll
            </button>
          </form>
        </div>
        {% endfor %}
      </div>
    </div>
  </div>
  {% endif %}

  <!-- Modal 5: View Fee Receipt Modal -->
  <div class="modal-backdrop" id="receiptModal">
    <div class="modal-window" style="max-width: 500px;">
      <div class="modal-header">
        <h3><i class="fa-solid fa-file-invoice-dollar" style="color: var(--success);"></i> Official Fee Receipt</h3>
        <button class="btn-icon" onclick="closeModal('receiptModal')"><i class="fa-solid fa-xmark"></i></button>
      </div>
      <div style="border: 1px dashed var(--border-strong); border-radius: 12px; padding: 1.25rem; background: var(--bg-surface-elevated);" id="printableReceiptArea">
        <div style="text-align: center; border-bottom: 1px solid var(--border-subtle); padding-bottom: 0.75rem; margin-bottom: 1rem;">
          <h4 style="font-size: 1.15rem; color: var(--primary);">AURACAMPUS UNIVERSITY</h4>
          <div style="font-size: 0.75rem; color: var(--text-muted);">Accounts & Bursar Electronic Receipt</div>
        </div>
        <div style="display: flex; justify-content: space-between; font-size: 0.85rem; margin: 6px 0;">
          <span style="color: var(--text-muted);">Receipt No:</span>
          <span id="receipt_id" style="font-weight: 700; font-family: monospace;"></span>
        </div>
        <div style="display: flex; justify-content: space-between; font-size: 0.85rem; margin: 6px 0;">
          <span style="color: var(--text-muted);">Payment Date:</span>
          <span id="receipt_date" style="font-weight: 600;"></span>
        </div>
        <div style="display: flex; justify-content: space-between; font-size: 0.85rem; margin: 6px 0;">
          <span style="color: var(--text-muted);">Payment Channel:</span>
          <span id="receipt_method" style="font-weight: 600;"></span>
        </div>
        <div style="display: flex; justify-content: space-between; font-size: 0.85rem; margin: 6px 0;">
          <span style="color: var(--text-muted);">Student Name:</span>
          <span style="font-weight: 700;">{{ current_student.name if current_student else 'Enrolled Student' }}</span>
        </div>
        <div style="border-top: 1px solid var(--border-subtle); margin-top: 1rem; padding-top: 0.75rem; display: flex; justify-content: space-between; align-items: center;">
          <span style="font-weight: 700; font-size: 1rem;">AMOUNT RECEIVED:</span>
          <span id="receipt_amount" style="font-size: 1.35rem; font-weight: 800; color: var(--success);">$0.00</span>
        </div>
        <div style="text-align: center; margin-top: 1rem; font-size: 0.7rem; color: var(--text-dim);">
          This is a system generated digital receipt verified by AuraCampus Cloud ERP.
        </div>
      </div>
      <div style="margin-top: 1.25rem; display: flex; justify-content: flex-end;">
        <button class="btn-primary" onclick="window.print()"><i class="fa-solid fa-print"></i> Print Receipt</button>
      </div>
    </div>
  </div>

  <!-- Toast Notification Container -->
  <div class="toast-container" id="toastContainer"></div>

  <!-- JavaScript Application Logic -->
  <script>
    // Theme Switcher Logic
    const themeToggleBtn = document.getElementById('themeToggleBtn');
    const htmlEl = document.documentElement;
    const savedTheme = localStorage.getItem('auracampus_theme') || 'dark';
    htmlEl.setAttribute('data-theme', savedTheme);
    updateThemeIcon(savedTheme);

    themeToggleBtn.addEventListener('click', () => {
      const current = htmlEl.getAttribute('data-theme');
      const next = current === 'dark' ? 'light' : 'dark';
      htmlEl.setAttribute('data-theme', next);
      localStorage.setItem('auracampus_theme', next);
      updateThemeIcon(next);
    });

    function updateThemeIcon(theme) {
      themeToggleBtn.innerHTML = theme === 'dark' 
        ? '<i class="fa-solid fa-moon"></i>' 
        : '<i class="fa-solid fa-sun" style="color: #f59e0b;"></i>';
    }

    // Modal Control Functions
    function openModal(modalId) {
      const modal = document.getElementById(modalId);
      if (modal) modal.classList.add('open');
    }

    function closeModal(modalId) {
      const modal = document.getElementById(modalId);
      if (modal) modal.classList.remove('open');
    }

    // Close on backdrop click
    document.querySelectorAll('.modal-backdrop').forEach(b => {
      b.addEventListener('click', (e) => {
        if (e.target === b) b.classList.remove('open');
      });
    });

    // Populate and open edit modal
    function openEditModal(studentId, name, course, email, rollNo, dept, year, sem, phone, cgpa, attendance, feesTotal, feesPaid) {
      const form = document.getElementById('editStudentForm');
      form.action = `/student/${studentId}/update`;
      document.getElementById('edit_name').value = name || '';
      document.getElementById('edit_course').value = course || '';
      document.getElementById('edit_email').value = email || '';
      document.getElementById('edit_roll').value = rollNo || '';
      document.getElementById('edit_dept').value = dept || '';
      document.getElementById('edit_year').value = year || '';
      document.getElementById('edit_sem').value = sem || '';
      document.getElementById('edit_phone').value = phone || '';
      document.getElementById('edit_cgpa').value = cgpa || '8.0';
      document.getElementById('edit_attendance').value = attendance || '85.0';
      document.getElementById('edit_feesTotal').value = feesTotal || '4500';
      document.getElementById('edit_feesPaid').value = feesPaid || '4500';
      openModal('editStudentModal');
    }

    function viewReceiptModal(id, date, amount, method) {
      document.getElementById('receipt_id').textContent = id;
      document.getElementById('receipt_date').textContent = date;
      document.getElementById('receipt_method').textContent = method;
      document.getElementById('receipt_amount').textContent = '$' + parseFloat(amount).toFixed(2);
      openModal('receiptModal');
    }

    // Filter Students Table (Live Search & Filter)
    function filterStudentTable() {
      const search = (document.getElementById('studentSearchInput')?.value || '').toLowerCase();
      const dept = (document.getElementById('departmentFilter')?.value || '').toLowerCase();
      const attFilter = document.getElementById('attendanceFilter')?.value || '';
      const rows = document.querySelectorAll('#studentsTable tbody tr');

      rows.forEach(row => {
        const name = row.getAttribute('data-name') || '';
        const roll = row.getAttribute('data-roll') || '';
        const email = row.getAttribute('data-email') || '';
        const rowDept = row.getAttribute('data-dept') || '';
        const att = parseFloat(row.getAttribute('data-att') || '0');

        let matchSearch = !search || name.includes(search) || roll.includes(search) || email.includes(search) || rowDept.includes(search);
        let matchDept = !dept || rowDept.includes(dept);
        let matchAtt = true;
        if (attFilter === 'above75') matchAtt = att >= 75;
        if (attFilter === 'below75') matchAtt = att < 75;

        row.style.display = (matchSearch && matchDept && matchAtt) ? '' : 'none';
      });
    }

    // Interactive Safe-Leave / Bunk Calculator
    {% if current_student %}
    const currentAttPercent = {{ current_student.attendance }};
    const totalClasses = {{ current_student.courses|sum(attribute='classesTotal') if current_student.courses else 100 }};
    const attendedClasses = {{ current_student.courses|sum(attribute='classesAttended') if current_student.courses else 85 }};

    function updateBunkCalc(target) {
      target = parseFloat(target);
      document.getElementById('targetPercentDisplay').textContent = target + '%';
      const icon = document.getElementById('bunkResultIcon');
      const heading = document.getElementById('bunkHeading');
      const subtext = document.getElementById('bunkSubtext');

      // Math for safe absences:
      // (attended) / (total + x) >= target/100
      // attended >= (target/100) * total + (target/100)*x
      // x <= (attended - target*total/100) / (target/100)
      if (currentAttPercent >= target) {
        const maxCanMiss = Math.floor((attendedClasses - (target / 100) * totalClasses) / (target / 100));
        icon.className = 'calc-result-icon safe';
        icon.innerHTML = '<i class="fa-solid fa-umbrella-beach"></i>';
        heading.innerHTML = `You can safely miss <span style="color: #34d399; font-size: 1.15rem;">${Math.max(0, maxCanMiss)}</span> upcoming lectures!`;
        subtext.textContent = `Your attendance will remain safely at or above ${target}%. Great buffer!`;
      } else {
        // Must attend y consecutive classes:
        // (attended + y) / (total + y) >= target/100
        // attended + y >= target*total/100 + target*y/100
        // y * (1 - target/100) >= (target*total/100 - attended)
        const targetFrac = target / 100;
        const needed = Math.ceil(((targetFrac * totalClasses) - attendedClasses) / (1 - targetFrac));
        icon.className = 'calc-result-icon danger';
        icon.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i>';
        heading.innerHTML = `Need to attend <span style="color: #f87171; font-size: 1.15rem;">${Math.max(1, needed)}</span> consecutive lectures!`;
        subtext.textContent = `Must attend without missing to raise attendance back up to ${target}%.`;
      }
    }
    // Initialize calculator
    if (document.getElementById('targetSlider')) {
      updateBunkCalc(75);
    }
    {% endif %}

    // Toast Notifications on Query Param Feedback
    const urlParams = new URLSearchParams(window.location.search);
    const msg = urlParams.get('msg');
    if (msg) {
      let toastText = 'Action completed successfully';
      if (msg === 'student_added') toastText = 'New student registered successfully!';
      if (msg === 'student_updated') toastText = 'Student profile updated!';
      if (msg === 'student_deleted') toastText = 'Student record deleted.';
      if (msg === 'fee_paid') toastText = 'Payment processed & receipt recorded!';
      if (msg === 'enrolled') toastText = 'Elective course added to timetable!';
      if (msg === 'dropped') toastText = 'Course dropped from schedule.';
      if (msg === 'attendance_updated') toastText = 'Attendance log updated!';
      if (msg === 'data_reset') toastText = 'Demo database re-seeded successfully!';

      showToast(toastText);
    }

    function showToast(text) {
      const container = document.getElementById('toastContainer');
      const toast = document.createElement('div');
      toast.className = 'toast success';
      toast.innerHTML = `<i class="fa-solid fa-circle-check" style="color: var(--success);"></i> <span>${text}</span>`;
      container.appendChild(toast);
      setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateY(10px)';
        setTimeout(() => toast.remove(), 300);
      }, 4000);
    }
  </script>
</body>
</html>

HTMLEOF

cat > /opt/studentapp/requirements.txt << 'REQEOF'
flask==3.0.3
boto3==1.34.131
gunicorn==22.0.0
REQEOF

pip3 install -r /opt/studentapp/requirements.txt || python3 -m pip install -r /opt/studentapp/requirements.txt

cat > /etc/systemd/system/studentapp.service << 'SVCEOF'
[Unit]
Description=AuraCampus Student ERP Flask App
After=network.target

[Service]
WorkingDirectory=/opt/studentapp
Environment=TABLE_NAME=StudentRecords
Environment=AWS_REGION=us-east-1
Environment=PORT=80
ExecStart=/usr/bin/python3 /opt/studentapp/app.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable studentapp
systemctl start studentapp
