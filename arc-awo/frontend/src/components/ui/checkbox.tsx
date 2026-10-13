import * as React from "react";
import { Check } from "lucide-react";
import { cn } from "@/lib/utils";

export interface CheckboxProps {
  checked?: boolean;
  disabled?: boolean;
  onCheckedChange?: (checked: boolean) => void;
  className?: string;
}

const Checkbox = React.forwardRef<HTMLButtonElement, CheckboxProps>(
  ({ checked = false, disabled, onCheckedChange, className }, ref) => (
    <button
      ref={ref}
      type="button"
      role="checkbox"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onCheckedChange?.(!checked)}
      className={cn(
        "flex h-4 w-4 shrink-0 items-center justify-center rounded border border-primary/50 ring-offset-background focus-visible:outline-none focus-visible:ring-2 disabled:cursor-not-allowed disabled:opacity-40",
        checked ? "bg-primary text-primary-foreground" : "bg-background",
        className
      )}
    >
      {checked ? <Check className="h-3 w-3" /> : null}
    </button>
  )
);
Checkbox.displayName = "Checkbox";

export { Checkbox };
