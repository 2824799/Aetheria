interface ToastProps {
  message: string;
  type: "success" | "error" | "info";
}

export default function Toast({ message, type }: ToastProps) {
  return (
    <div className={`toast-container ${type}`}>
      {message}
    </div>
  );
}
