import smtplib
import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
from app.config import settings

def send_backup_email(zip_bytes: bytes, filename: str, subject: str, body: str, receiver_email: str = None) -> dict:
    """
    Sends the generated database ZIP backup as an email attachment using Gmail SMTP.
    Validates env credentials and establishes a secure TLS connection.
    Returns a dictionary indicating success or failure.
    """
    smtp_email = settings.smtp_email
    smtp_password = settings.smtp_password
    if not receiver_email:
        receiver_email = settings.backup_receiver_email

    if not smtp_email or not smtp_password or not receiver_email:
        return {
            "success": False,
            "error": "Email Backup credentials are not set. Please configure SMTP_EMAIL, SMTP_PASSWORD, and BACKUP_RECEIVER_EMAIL in your environment/settings."
        }

    # 1. Construct MIME multipart email message
    msg = MIMEMultipart()
    msg['From'] = smtp_email
    msg['To'] = receiver_email
    msg['Subject'] = subject

    msg.attach(MIMEText(body, 'plain'))

    # 2. Add ZIP attachment
    try:
        part = MIMEBase('application', 'zip')
        part.set_payload(zip_bytes)
        encoders.encode_base64(part)
        part.add_header('Content-Disposition', f'attachment; filename="{filename}"')
        msg.attach(part)
    except Exception as e:
        return {
            "success": False,
            "error": f"Failed to package attachment: {str(e)}"
        }

    # 3. Establish connection and send email
    try:
        # Establish SMTP connection with TLS (port 587)
        server = smtplib.SMTP('smtp.gmail.com', 587, timeout=20)
        server.starttls()  # Upgrade to secure connection
        server.login(smtp_email, smtp_password)
        server.sendmail(smtp_email, receiver_email, msg.as_string())
        server.quit()
        return {
            "success": True,
            "message": f"Backup email successfully sent to {receiver_email}"
        }
    except smtplib.SMTPAuthenticationError:
        return {
            "success": False,
            "error": "SMTP authentication failed. Verify that your Gmail App Password is correct."
        }
    except Exception as e:
        return {
            "success": False,
            "error": f"SMTP connection or delivery failed: {str(e)}"
        }
