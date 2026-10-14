// مولَّد من Supabase (generate_typescript_types) — لا تعدّله يدويًا.
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      accounts: {
        Row: {
          code: string
          created_at: string
          id: number
          is_active: boolean
          is_postable: boolean
          is_treasury: boolean
          name: string
          parent_id: number | null
          type: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: never
          is_active?: boolean
          is_postable?: boolean
          is_treasury?: boolean
          name: string
          parent_id?: number | null
          type: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: never
          is_active?: boolean
          is_postable?: boolean
          is_treasury?: boolean
          name?: string
          parent_id?: number | null
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "accounts_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      customers: {
        Row: {
          address: string | null
          created_at: string
          id: number
          is_active: boolean
          name: string
          notes: string | null
          phone: string | null
        }
        Insert: {
          address?: string | null
          created_at?: string
          id?: never
          is_active?: boolean
          name: string
          notes?: string | null
          phone?: string | null
        }
        Update: {
          address?: string | null
          created_at?: string
          id?: never
          is_active?: boolean
          name?: string
          notes?: string | null
          phone?: string | null
        }
        Relationships: []
      }
      doc_counters: {
        Row: {
          kind: string
          last_no: number
        }
        Insert: {
          kind: string
          last_no?: number
        }
        Update: {
          kind?: string
          last_no?: number
        }
        Relationships: []
      }
      item_stock: {
        Row: {
          avg_cost: number
          item_id: number
          qty: number
          value: number
        }
        Insert: {
          avg_cost?: number
          item_id: number
          qty?: number
          value?: number
        }
        Update: {
          avg_cost?: number
          item_id?: number
          qty?: number
          value?: number
        }
        Relationships: [
          {
            foreignKeyName: "item_stock_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: true
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
        ]
      }
      items: {
        Row: {
          code: string
          created_at: string
          id: number
          is_active: boolean
          name: string
          sale_price: number | null
          type: string
          unit: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: never
          is_active?: boolean
          name: string
          sale_price?: number | null
          type: string
          unit: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: never
          is_active?: boolean
          name?: string
          sale_price?: number | null
          type?: string
          unit?: string
        }
        Relationships: []
      }
      journal_entries: {
        Row: {
          created_at: string
          created_by: string
          description: string
          entry_date: string
          entry_no: number
          id: number
          reverses_entry_id: number | null
          source_id: number | null
          source_type: string
        }
        Insert: {
          created_at?: string
          created_by: string
          description: string
          entry_date: string
          entry_no: number
          id?: never
          reverses_entry_id?: number | null
          source_id?: number | null
          source_type: string
        }
        Update: {
          created_at?: string
          created_by?: string
          description?: string
          entry_date?: string
          entry_no?: number
          id?: never
          reverses_entry_id?: number | null
          source_id?: number | null
          source_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "journal_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_entries_reverses_entry_id_fkey"
            columns: ["reverses_entry_id"]
            isOneToOne: true
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      journal_lines: {
        Row: {
          account_id: number
          credit: number
          customer_id: number | null
          debit: number
          description: string | null
          entry_id: number
          id: number
          supplier_id: number | null
        }
        Insert: {
          account_id: number
          credit?: number
          customer_id?: number | null
          debit?: number
          description?: string | null
          entry_id: number
          id?: never
          supplier_id?: number | null
        }
        Update: {
          account_id?: number
          credit?: number
          customer_id?: number | null
          debit?: number
          description?: string | null
          entry_id?: number
          id?: never
          supplier_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "journal_lines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_lines_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_lines_entry_id_fkey"
            columns: ["entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "journal_lines_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          email: string | null
          full_name: string | null
          id: string
          role: string
        }
        Insert: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          id: string
          role?: string
        }
        Update: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          id?: string
          role?: string
        }
        Relationships: []
      }
      purchase_invoice_lines: {
        Row: {
          id: number
          invoice_id: number
          item_id: number
          line_total: number
          qty: number
          unit_price: number
        }
        Insert: {
          id?: never
          invoice_id: number
          item_id: number
          line_total: number
          qty: number
          unit_price: number
        }
        Update: {
          id?: never
          invoice_id?: number
          item_id?: number
          line_total?: number
          qty?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "purchase_invoice_lines_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "purchase_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_invoice_lines_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_invoices: {
        Row: {
          created_at: string
          doc_date: string
          doc_no: number
          id: number
          journal_entry_id: number
          notes: string | null
          payment_voucher_id: number | null
          supplier_id: number
          total: number
        }
        Insert: {
          created_at?: string
          doc_date: string
          doc_no: number
          id?: never
          journal_entry_id: number
          notes?: string | null
          payment_voucher_id?: number | null
          supplier_id: number
          total: number
        }
        Update: {
          created_at?: string
          doc_date?: string
          doc_no?: number
          id?: never
          journal_entry_id?: number
          notes?: string | null
          payment_voucher_id?: number | null
          supplier_id?: number
          total?: number
        }
        Relationships: [
          {
            foreignKeyName: "purchase_invoices_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: true
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_invoices_payment_voucher_id_fkey"
            columns: ["payment_voucher_id"]
            isOneToOne: true
            referencedRelation: "vouchers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_invoices_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      settings: {
        Row: {
          company_address: string | null
          company_name: string
          company_phone: string | null
          currency_name: string
          currency_symbol: string
          id: number
          lock_date: string | null
        }
        Insert: {
          company_address?: string | null
          company_name: string
          company_phone?: string | null
          currency_name?: string
          currency_symbol?: string
          id?: number
          lock_date?: string | null
        }
        Update: {
          company_address?: string | null
          company_name?: string
          company_phone?: string | null
          currency_name?: string
          currency_symbol?: string
          id?: number
          lock_date?: string | null
        }
        Relationships: []
      }
      stock_adjustments: {
        Row: {
          counted_qty: number
          created_at: string
          doc_date: string
          doc_no: number
          id: number
          item_id: number
          journal_entry_id: number
          notes: string | null
          system_qty: number
          total_cost: number
          unit_cost: number
        }
        Insert: {
          counted_qty: number
          created_at?: string
          doc_date: string
          doc_no: number
          id?: never
          item_id: number
          journal_entry_id: number
          notes?: string | null
          system_qty: number
          total_cost: number
          unit_cost: number
        }
        Update: {
          counted_qty?: number
          created_at?: string
          doc_date?: string
          doc_no?: number
          id?: never
          item_id?: number
          journal_entry_id?: number
          notes?: string | null
          system_qty?: number
          total_cost?: number
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "stock_adjustments_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_adjustments_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: true
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      stock_movements: {
        Row: {
          created_at: string
          id: number
          item_id: number
          journal_entry_id: number
          kind: string
          movement_date: string
          qty_in: number
          qty_out: number
          reverses_movement_id: number | null
          source_id: number | null
          source_type: string
          total_cost: number
          unit_cost: number
        }
        Insert: {
          created_at?: string
          id?: never
          item_id: number
          journal_entry_id: number
          kind: string
          movement_date: string
          qty_in?: number
          qty_out?: number
          reverses_movement_id?: number | null
          source_id?: number | null
          source_type: string
          total_cost?: number
          unit_cost?: number
        }
        Update: {
          created_at?: string
          id?: never
          item_id?: number
          journal_entry_id?: number
          kind?: string
          movement_date?: string
          qty_in?: number
          qty_out?: number
          reverses_movement_id?: number | null
          source_id?: number | null
          source_type?: string
          total_cost?: number
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "stock_movements_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_movements_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: false
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_movements_reverses_movement_id_fkey"
            columns: ["reverses_movement_id"]
            isOneToOne: true
            referencedRelation: "stock_movements"
            referencedColumns: ["id"]
          },
        ]
      }
      suppliers: {
        Row: {
          address: string | null
          created_at: string
          id: number
          is_active: boolean
          name: string
          notes: string | null
          phone: string | null
        }
        Insert: {
          address?: string | null
          created_at?: string
          id?: never
          is_active?: boolean
          name: string
          notes?: string | null
          phone?: string | null
        }
        Update: {
          address?: string | null
          created_at?: string
          id?: never
          is_active?: boolean
          name?: string
          notes?: string | null
          phone?: string | null
        }
        Relationships: []
      }
      system_accounts: {
        Row: {
          account_id: number
          key: string
        }
        Insert: {
          account_id: number
          key: string
        }
        Update: {
          account_id?: number
          key?: string
        }
        Relationships: [
          {
            foreignKeyName: "system_accounts_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      vouchers: {
        Row: {
          account_id: number | null
          amount: number
          created_at: string
          customer_id: number | null
          doc_date: string
          doc_no: number
          id: number
          journal_entry_id: number
          kind: string
          notes: string | null
          party_kind: string
          supplier_id: number | null
          treasury_account_id: number
        }
        Insert: {
          account_id?: number | null
          amount: number
          created_at?: string
          customer_id?: number | null
          doc_date: string
          doc_no: number
          id?: never
          journal_entry_id: number
          kind: string
          notes?: string | null
          party_kind: string
          supplier_id?: number | null
          treasury_account_id: number
        }
        Update: {
          account_id?: number | null
          amount?: number
          created_at?: string
          customer_id?: number | null
          doc_date?: string
          doc_no?: number
          id?: never
          journal_entry_id?: number
          kind?: string
          notes?: string | null
          party_kind?: string
          supplier_id?: number | null
          treasury_account_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "vouchers_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vouchers_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vouchers_journal_entry_id_fkey"
            columns: ["journal_entry_id"]
            isOneToOne: true
            referencedRelation: "journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vouchers_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vouchers_treasury_account_id_fkey"
            columns: ["treasury_account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      account_statement: {
        Args: { p_account_id: number; p_from?: string; p_to?: string }
        Returns: {
          balance: string
          credit: string
          debit: string
          description: string
          entry_date: string
          entry_id: number
          entry_no: number
          source_type: string
        }[]
      }
      active_openings: {
        Args: never
        Returns: {
          entry_date: string
          entry_id: number
          entry_no: number
          part: string
        }[]
      }
      cancel_journal_entry: { Args: { p_entry_id: number }; Returns: number }
      cancel_purchase_invoice: {
        Args: { p_invoice_id: number }
        Returns: number
      }
      cancel_stock_adjustment: {
        Args: { p_adjustment_id: number }
        Returns: number
      }
      cancel_voucher: { Args: { p_voucher_id: number }; Returns: number }
      item_movements: {
        Args: { p_from?: string; p_item_id: number; p_to?: string }
        Returns: {
          balance_qty: string
          balance_value: string
          doc_no: number
          journal_entry_id: number
          kind: string
          movement_date: string
          movement_id: number
          qty_in: string
          qty_out: string
          source_id: number
          source_type: string
          total_cost: string
          unit_cost: string
        }[]
      }
      journal_entry_list: {
        Args: { p_from?: string; p_search?: string; p_to?: string }
        Returns: {
          description: string
          entry_date: string
          entry_no: number
          id: number
          reversed_by_entry_id: number
          reverses_entry_id: number
          source_type: string
          total: string
        }[]
      }
      party_balances: {
        Args: { p_as_of?: string; p_party_kind: string }
        Returns: {
          balance: string
          party_id: number
        }[]
      }
      party_statement: {
        Args: {
          p_from?: string
          p_party_id: number
          p_party_kind: string
          p_to?: string
        }
        Returns: {
          balance: string
          credit: string
          debit: string
          description: string
          entry_date: string
          entry_id: number
          entry_no: number
          source_type: string
        }[]
      }
      post_journal_entry: {
        Args: {
          p_description: string
          p_entry_date: string
          p_lines: Json
          p_source_type: string
        }
        Returns: number
      }
      post_opening_balances: {
        Args: {
          p_difference_to_capital?: boolean
          p_entry_date: string
          p_lines: Json
        }
        Returns: number
      }
      post_party_opening_balances: {
        Args: {
          p_difference_to_capital?: boolean
          p_entry_date: string
          p_lines: Json
        }
        Returns: number
      }
      post_purchase_invoice: {
        Args: {
          p_doc_date: string
          p_lines: Json
          p_notes?: string
          p_paid_treasury_account_id?: number
          p_supplier_id: number
        }
        Returns: number
      }
      post_stock_adjustment: {
        Args: {
          p_counted_qty: string
          p_doc_date: string
          p_item_id: number
          p_notes?: string
        }
        Returns: number
      }
      post_stock_opening: {
        Args: {
          p_difference_to_capital?: boolean
          p_entry_date: string
          p_lines: Json
        }
        Returns: number
      }
      post_voucher: {
        Args: {
          p_amount: string
          p_doc_date: string
          p_kind: string
          p_notes?: string
          p_party_id: number
          p_party_kind: string
          p_treasury_account_id: number
        }
        Returns: number
      }
      purchase_invoice_list: {
        Args: { p_from?: string; p_search?: string; p_to?: string }
        Returns: {
          doc_date: string
          doc_no: number
          id: number
          is_cancelled: boolean
          journal_entry_id: number
          notes: string
          payment_voucher_id: number
          supplier_name: string
          total: string
        }[]
      }
      stock_adjustment_list: {
        Args: { p_from?: string; p_search?: string; p_to?: string }
        Returns: {
          counted_qty: string
          doc_date: string
          doc_no: number
          id: number
          is_cancelled: boolean
          item_code: string
          item_name: string
          journal_entry_id: number
          notes: string
          system_qty: string
          total_cost: string
        }[]
      }
      stock_balances: {
        Args: never
        Returns: {
          avg_cost: string
          code: string
          is_active: boolean
          item_id: number
          name: string
          qty: string
          type: string
          unit: string
          value: string
        }[]
      }
      trial_balance: {
        Args: { p_as_of?: string }
        Returns: {
          account_id: number
          code: string
          credit: string
          debit: string
          name: string
          type: string
        }[]
      }
      voucher_list: {
        Args: {
          p_from?: string
          p_kind: string
          p_search?: string
          p_to?: string
        }
        Returns: {
          amount: string
          doc_date: string
          doc_no: number
          id: number
          is_cancelled: boolean
          journal_entry_id: number
          notes: string
          party_kind: string
          party_name: string
          treasury: string
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never
